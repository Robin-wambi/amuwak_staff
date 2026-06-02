import 'package:supabase_flutter/supabase_flutter.dart';

import '../orders/order.dart';
import '../orders/order_status.dart';

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
      final orders =
          rows.where((r) => r['deleted_at'] == null).toList(growable: false);
      if (orders.isEmpty) return const <LaundryOrder>[];
      final ids = orders.map((r) => r['id'] as String).toList();
      final proofRows = await _supabase
          .from('proof_events')
          .select()
          .inFilter('order_id', ids);
      final grouped = <String, List<Map<String, dynamic>>>{};
      for (final p in proofRows) {
        (grouped[p['order_id'] as String] ??= <Map<String, dynamic>>[]).add(p);
      }
      return orders
          .map((r) => LaundryOrder.fromSupabase(
                r,
                grouped[r['id'] as String] ?? const [],
              ))
          .toList(growable: false);
    });
  }

  Stream<LaundryOrder?> watchById(String orderId) {
    return _supabase
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('id', orderId)
        .asyncMap((rows) async {
      final match =
          rows.where((r) => r['deleted_at'] == null).toList(growable: false);
      if (match.isEmpty) return null;
      final proofRows = await _supabase
          .from('proof_events')
          .select()
          .eq('order_id', orderId);
      return LaundryOrder.fromSupabase(
        match.first,
        proofRows.cast<Map<String, dynamic>>(),
      );
    });
  }

  // ----- WRITE -----

  Future<void> upsertOrder(LaundryOrder order,
      {required String actorStaffId}) async {
    final now = _clock();
    await _supabase
        .from('orders')
        .upsert(_toPayload(order, actorStaffId, now: now));
  }

  /// Updates an order's status. [updatedAt] is optional and kept for call-site
  /// compatibility with the offline path (where it stabilised the outbox dedup
  /// key); online it just sets the row's `updated_at`.
  Future<void> updateStatus(
    String orderId,
    OrderStatus newStatus, {
    required String actorStaffId,
    DateTime? updatedAt,
  }) async {
    final now = updatedAt ?? _clock();
    final dbStatus = newStatus.toDbString();
    await _supabase.from('orders').update(<String, dynamic>{
      'status': dbStatus,
      'updated_at': now.toUtc().toIso8601String(),
    }).eq('id', orderId);
  }

  // ----- PRIVATE HELPERS -----

  Map<String, dynamic> _toPayload(LaundryOrder order, String actorStaffId,
          {required DateTime now}) =>
      {
        'id': order.orderId,
        'order_code': order.orderCode,
        'customer_id': order.customerId,
        'customer_name': order.customerName,
        'phone': order.phone,
        'address': order.address,
        'service_type': order.serviceType.toDbString(),
        'status': order.status.toDbString(),
        'intake_method': order.intakeMethod,
        'fulfillment_method': order.fulfillmentMethod,
        'item_count': order.itemCount,
        'notes': order.notes,
        'scheduled_for': order.scheduledFor?.toUtc().toIso8601String(),
        'intake_recorded_by': actorStaffId,
        'created_by': actorStaffId,
        'created_at': now.toUtc().toIso8601String(),
        'updated_at': now.toUtc().toIso8601String(),
      };
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
