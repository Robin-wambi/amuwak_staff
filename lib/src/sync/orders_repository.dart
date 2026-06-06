import 'dart:developer' as developer;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../orders/order.dart';
import '../orders/order_status.dart';
import '../orders/pricing/pricing_calculator.dart';
import '../orders/pricing/pricing_inputs.dart';
import '../shared/order_code.dart';
import 'supabase_mappers.dart';
import 'supabase_payloads.dart';

/// Read/write repository for orders — ONLINE-ONLY mode.
///
/// Reads stream live from Supabase (`orders` realtime stream, with a follow-up
/// `proof_events` select to hydrate the joined proof events). Writes go
/// directly to Supabase. The previous offline-first implementation (local
/// Drift reads + outbox-queued writes) is preserved verbatim in the commented
/// `OFFLINE` block at the bottom of this file so it can be re-enabled later.
///
/// Joined proof events are fetched via a follow-up query rather than a single
/// join — Supabase realtime streams are single-table, and an order's status
/// changes when proof is captured, so the orders stream re-emits and the join
/// refetches. Two simple queries are easier to reason about and the cost (one
/// extra `SELECT` per emission) is negligible at the dashboard's scale.
class OrdersRepository {
  OrdersRepository(
    this._supabase, {
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final SupabaseClient _supabase;
  final DateTime Function() _clock;

  // ----- READ -----

  Stream<List<LaundryOrder>> watchAll() {
    // Soft-deleted orders (back-office tombstones) must not surface to the
    // rider, mirroring the deletedAt filter on the other read repos. `.stream()`
    // can't express `IS NULL`, so we filter client-side.
    return _supabase
        .from('orders')
        .stream(primaryKey: ['id'])
        .order('created_at')
        .asyncMap((rows) async {
      final ids = rows
          .where((r) => r['deleted_at'] == null)
          .map((r) => r['id'] as String)
          .toList(growable: false);
      if (ids.isEmpty) return const <LaundryOrder>[];
      // A transient failure on this secondary fetch (network blip, RLS) must
      // not error the whole stream — degrade to orders without proof events.
      // The orders stream re-emits on the next change and recovers.
      List<Map<String, dynamic>> proofRows;
      try {
        proofRows = await _supabase
            .from('proof_events')
            .select()
            .inFilter('order_id', ids);
      } catch (e, st) {
        developer.log(
          'watchAll: proof_events fetch failed; showing orders without '
          'proof events this cycle.',
          name: 'OrdersRepository',
          error: e,
          stackTrace: st,
        );
        proofRows = const [];
      }
      return hydrateOrders(rows, proofRows);
    });
  }

  Stream<LaundryOrder?> watchById(String orderId) {
    return _supabase
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('id', orderId)
        .asyncMap((rows) async {
      final hasLiveOrder = rows.any((r) => r['deleted_at'] == null);
      if (!hasLiveOrder) return null;
      // Mirror watchAll: a transient failure on the secondary proof_events
      // fetch must degrade to the order without proof events, not error the
      // stream permanently. The orders stream re-emits and recovers.
      List<Map<String, dynamic>> proofRows;
      try {
        proofRows = (await _supabase
                .from('proof_events')
                .select()
                .eq('order_id', orderId))
            .cast<Map<String, dynamic>>();
      } catch (e, st) {
        developer.log(
          'watchById: proof_events fetch failed; showing order without '
          'proof events this cycle.',
          name: 'OrdersRepository',
          error: e,
          stackTrace: st,
        );
        proofRows = const [];
      }
      return hydrateOrder(rows, proofRows);
    });
  }

  // ----- WRITE -----

  /// Returns a copy of [order] with `totalUgx` recomputed from its pricing
  /// inputs. The single chokepoint that keeps the stored total honest — a
  /// caller can never persist a total that disagrees with the weights/rate/
  /// line-items/adjustment.
  static LaundryOrder recomputeOrderTotal(LaundryOrder order) {
    final t = recomputeTotal(PricingInputs(
      ratePerKgUgx: order.ratePerKgSnapshotUgx,
      estimatedWeightKg: order.estimatedWeightKg,
      finalWeightKg: order.finalWeightKg,
      lineItems: order.lineItems,
      manualAdjustmentUgx: order.manualAdjustmentUgx,
    ));
    return order.copyWith(totalUgx: t.total);
  }

  /// Resolves the rate to freeze into a new order: the customer's override if
  /// set, otherwise the global default.
  static double resolveRatePerKg({
    required double? customRate,
    required double defaultRate,
  }) =>
      customRate ?? defaultRate;

  /// Reserves the next human-facing order code (e.g. `AMW-2026-0042`) from the
  /// server via the `next_order_code()` RPC. Owning this here keeps "how an
  /// order code is minted" in the repository layer rather than wired into the
  /// UI — the New Pickup screen calls this, caches the result for retry, then
  /// hands the coded order to [upsertOrder]. The RPC throws when offline, which
  /// the form surfaces as a retryable error.
  Future<String> reserveOrderCode() async {
    final result = await _supabase.rpc('next_order_code');
    return parseOrderCodeRpcResult(result);
  }

  /// Creates an order. **Insert-only in practice:** the only caller is the New
  /// Pickup flow creating a brand-new order; subsequent changes go through
  /// [updateStatus], never back through here. It is implemented as an `upsert`
  /// so a submit retry with the same (cached) `orderId` is idempotent rather
  /// than a duplicate-key crash.
  ///
  /// Caveat: because `upsert` writes every column on conflict, calling this for
  /// an *existing* order would overwrite `created_at`/`created_by` with the
  /// current actor/time. Don't repurpose it for edits — add a dedicated update
  /// method (or a DB rule pinning the creation columns) if an edit flow is ever
  /// needed.
  Future<void> upsertOrder(LaundryOrder order,
      {required String actorStaffId}) async {
    final now = _clock();
    final priced = recomputeOrderTotal(order);
    await _supabase
        .from('orders')
        .upsert(orderUpsertPayload(priced, actorStaffId: actorStaffId, now: now));
  }

  /// Updates only the pricing columns (+ updated_at), recomputing total_ugx.
  /// Unlike [upsertOrder] this never touches created_at/created_by.
  Future<void> updatePricing(LaundryOrder order,
      {required String actorStaffId}) async {
    final priced = recomputeOrderTotal(order);
    final updated = await _supabase.from('orders').update({
      'estimated_weight_kg': priced.estimatedWeightKg,
      'final_weight_kg': priced.finalWeightKg,
      'line_items': priced.lineItems.map((i) => i.toJson()).toList(),
      'manual_adjustment_ugx': priced.manualAdjustmentUgx,
      'total_ugx': priced.totalUgx,
      'updated_at': _clock().toUtc().toIso8601String(),
    }).eq('id', priced.orderId).select('id');
    if (updated.isEmpty) {
      throw StateError('updatePricing: no order with id "${priced.orderId}"');
    }
  }

  /// Updates an order's status. [updatedAt] is optional and kept for call-site
  /// compatibility with the offline path (where it stabilised the outbox dedup
  /// key); online it just sets the row's `updated_at`.
  ///
  /// Throws a [StateError] when no order matched [orderId] (e.g. it was
  /// soft-deleted server-side while the rider was on the capture screen) —
  /// matching the old offline path so callers don't treat a no-op as success.
  Future<void> updateStatus(
    String orderId,
    OrderStatus newStatus, {
    required String actorStaffId,
    DateTime? updatedAt,
  }) async {
    final now = updatedAt ?? _clock();
    final updated = await _supabase
        .from('orders')
        .update(orderStatusUpdatePayload(newStatus, now: now))
        .eq('id', orderId)
        .select('id');
    if (updated.isEmpty) {
      throw StateError('updateStatus: no order with id "$orderId"');
    }
  }
}

/* ============================================================================
 * OFFLINE (Drift local reads + outbox-queued writes) — PRESERVED FOR RE-ENABLE
 * ----------------------------------------------------------------------------
 * The offline-first implementation below was the production path before the
 * online-only switch. It reads from the local Drift `orders`/`proof_events`
 * tables and queues writes onto the outbox for the SyncOrchestrator to dispatch.
 * To restore offline support, re-wire `ordersRepositoryProvider` to pass the
 * AppDatabase + OutboxRepository and swap this body back in.
 *
 * import 'package:drift/drift.dart' show Value;
 * import '../data/app_database.dart';
 * import 'outbox_repository.dart';
 *
 * class OrdersRepository {
 *   OrdersRepository(this._db, {OutboxRepository? outbox, DateTime Function()? clock})
 *       : _outbox = outbox, _clock = clock ?? DateTime.now;
 *   final AppDatabase _db;
 *   final OutboxRepository? _outbox;
 *   final DateTime Function() _clock;
 *
 *   Stream<List<LaundryOrder>> watchAll() {
 *     return (_db.select(_db.orders)..where((t) => t.deletedAt.isNull()))
 *         .watch()
 *         .asyncMap((rows) async {
 *       if (rows.isEmpty) return const <LaundryOrder>[];
 *       final ids = rows.map((r) => r.id).toList();
 *       final events = await (_db.select(_db.proofEvents)
 *             ..where((t) => t.orderId.isIn(ids))).get();
 *       final grouped = <String, List<ProofEvent>>{};
 *       for (final e in events) {
 *         grouped.putIfAbsent(e.orderId, () => <ProofEvent>[]).add(e);
 *       }
 *       return rows
 *           .map((r) => LaundryOrder.fromDriftRow(r, grouped[r.id] ?? const []))
 *           .toList(growable: false);
 *     });
 *   }
 *
 *   Stream<LaundryOrder?> watchById(String orderId) {
 *     return (_db.select(_db.orders)
 *           ..where((t) => t.id.equals(orderId))
 *           ..where((t) => t.deletedAt.isNull()))
 *         .watchSingleOrNull()
 *         .asyncMap((row) async {
 *       if (row == null) return null;
 *       final events = await (_db.select(_db.proofEvents)
 *             ..where((t) => t.orderId.equals(orderId))).get();
 *       return LaundryOrder.fromDriftRow(row, events);
 *     });
 *   }
 *
 *   Future<void> upsertOrder(LaundryOrder order, {required String actorStaffId}) async {
 *     final outbox = _requireOutbox();
 *     final now = _clock();
 *     await _db.transaction(() async {
 *       await _db.into(_db.orders).insertOnConflictUpdate(
 *             _toCompanion(order, actorStaffId, now: now));
 *       await outbox.enqueue(
 *         id: OutboxRepository.dedupKeyFor(
 *           forTable: 'orders', op: 'insert', rowId: order.orderId,
 *           extra: now.toUtc().toIso8601String()),
 *         forTable: 'orders', op: 'insert', rowId: order.orderId,
 *         payload: _toPayload(order, actorStaffId, now: now));
 *     });
 *   }
 *
 *   Future<void> updateStatus(String orderId, OrderStatus newStatus,
 *       {required String actorStaffId, DateTime? updatedAt}) async {
 *     final outbox = _requireOutbox();
 *     final now = updatedAt ?? _clock();
 *     final dbStatus = newStatus.toDbString();
 *     await _db.transaction(() async {
 *       final affected = await (_db.update(_db.orders)
 *             ..where((t) => t.id.equals(orderId)))
 *           .write(OrdersCompanion(status: Value(dbStatus), updatedAt: Value(now)));
 *       if (affected == 0) {
 *         throw StateError('updateStatus: no order with id "$orderId"');
 *       }
 *       await outbox.enqueue(
 *         id: OutboxRepository.dedupKeyFor(
 *           forTable: 'orders', op: 'update', rowId: orderId,
 *           extra: '$dbStatus:${now.toUtc().toIso8601String()}'),
 *         forTable: 'orders', op: 'update', rowId: orderId,
 *         payload: <String, dynamic>{
 *           'id': orderId, 'status': dbStatus,
 *           'updated_at': now.toUtc().toIso8601String()});
 *     });
 *   }
 *
 *   OutboxRepository _requireOutbox() {
 *     final o = _outbox;
 *     if (o == null) {
 *       throw StateError('OrdersRepository was constructed without an OutboxRepository; '
 *           'write methods are unavailable.');
 *     }
 *     return o;
 *   }
 *
 *   OrdersCompanion _toCompanion(LaundryOrder order, String actorStaffId,
 *       {required DateTime now}) {
 *     return OrdersCompanion(
 *       id: Value(order.orderId),
 *       orderCode: Value(order.orderCode),
 *       customerId: Value(order.customerId),
 *       customerName: Value(order.customerName),
 *       phone: Value(order.phone),
 *       address: Value(order.address),
 *       serviceType: Value(order.serviceType.toDbString()),
 *       status: Value(order.status.toDbString()),
 *       intakeMethod: Value(order.intakeMethod),
 *       fulfillmentMethod: Value(order.fulfillmentMethod),
 *       itemCount: Value(order.itemCount),
 *       notes: Value(order.notes),
 *       scheduledFor: Value(order.scheduledFor),
 *       intakeRecordedBy: Value(actorStaffId),
 *       createdBy: Value(actorStaffId),
 *       createdAt: Value(now),
 *       updatedAt: Value(now),
 *     );
 *   }
 * }
 * ========================================================================== */
