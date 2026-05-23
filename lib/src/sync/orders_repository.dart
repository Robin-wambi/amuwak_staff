import 'package:drift/drift.dart' show Value;
import 'package:uuid/uuid.dart';

import '../data/app_database.dart';
import '../orders/order.dart';
import '../orders/order_status.dart';
import 'outbox_repository.dart';

/// Read/write repository for orders.
///
/// Joined proof events are fetched via a follow-up query rather than a single
/// joined `.watch()` — Drift's joined streams emit flat rows that need
/// Dart-side grouping inside the stream reducer, which is fragile under
/// re-emission. Two simple queries are easier to reason about and the
/// performance cost (one extra `SELECT` per emission) is negligible for the
/// dashboard's order-list scale.
///
/// Write methods ([upsertOrder], [updateStatus]) require an [OutboxRepository]
/// to be supplied at construction time. Callers that only need the read API
/// can omit it; attempting a write on a read-only-configured instance throws
/// a [StateError].
class OrdersRepository {
  OrdersRepository(
    this._db, {
    OutboxRepository? outbox,
    DateTime Function()? clock,
    String Function()? uuid,
  })  : _outbox = outbox,
        _clock = clock ?? DateTime.now,
        _uuid = uuid ?? _defaultUuid;

  final AppDatabase _db;
  final OutboxRepository? _outbox;
  final DateTime Function() _clock;
  final String Function() _uuid;

  static String _defaultUuid() => const Uuid().v4();

  // ----- READ -----

  Stream<List<LaundryOrder>> watchAll() {
    // Soft-deleted orders (back-office tombstones synced via deletedAt) must
    // not surface to the rider. Matches the deletedAt filter on the other
    // read repos (CustomersRepository, StaffRepository, ProofEventsRepository).
    return (_db.select(_db.orders)..where((t) => t.deletedAt.isNull()))
        .watch()
        .asyncMap((rows) async {
      if (rows.isEmpty) return const <LaundryOrder>[];
      final ids = rows.map((r) => r.id).toList();
      final events = await (_db.select(_db.proofEvents)
            ..where((t) => t.orderId.isIn(ids)))
          .get();
      final grouped = <String, List<ProofEvent>>{};
      for (final e in events) {
        grouped.putIfAbsent(e.orderId, () => <ProofEvent>[]).add(e);
      }
      return rows
          .map((r) => LaundryOrder.fromDriftRow(r, grouped[r.id] ?? const []))
          .toList(growable: false);
    });
  }

  Stream<LaundryOrder?> watchById(String orderId) {
    // Two chained `..where(...)` clauses AND together; avoids needing the `&`
    // operator from drift's full import (kept narrow on this file via `show
    // Value`).
    return (_db.select(_db.orders)
          ..where((t) => t.id.equals(orderId))
          ..where((t) => t.deletedAt.isNull()))
        .watchSingleOrNull()
        .asyncMap((row) async {
      if (row == null) return null;
      final events = await (_db.select(_db.proofEvents)
            ..where((t) => t.orderId.equals(orderId)))
          .get();
      return LaundryOrder.fromDriftRow(row, events);
    });
  }

  // ----- WRITE -----

  Future<void> upsertOrder(LaundryOrder order,
      {required String actorStaffId}) async {
    final outbox = _requireOutbox();
    final now = _clock();
    await _db.transaction(() async {
      await _db.into(_db.orders).insertOnConflictUpdate(
            _toCompanion(order, actorStaffId, now: now),
          );
      await outbox.enqueue(
        id: _uuid(),
        forTable: 'orders',
        op: 'insert',
        rowId: order.orderId,
        payload: _toPayload(order, actorStaffId, now: now),
      );
    });
  }

  Future<void> updateStatus(String orderId, OrderStatus newStatus,
      {required String actorStaffId}) async {
    final outbox = _requireOutbox();
    final now = _clock();
    final dbStatus = newStatus.toDbString();
    await _db.transaction(() async {
      final affected = await (_db.update(_db.orders)
            ..where((t) => t.id.equals(orderId)))
          .write(OrdersCompanion(status: Value(dbStatus), updatedAt: Value(now)));
      if (affected == 0) {
        throw StateError('updateStatus: no order with id "$orderId"');
      }
      await outbox.enqueue(
        id: _uuid(),
        forTable: 'orders',
        op: 'update',
        rowId: orderId,
        payload: <String, dynamic>{
          'id': orderId,
          'status': dbStatus,
          'updated_at': now.toUtc().toIso8601String(),
        },
      );
    });
  }

  // ----- PRIVATE HELPERS -----

  OutboxRepository _requireOutbox() {
    final o = _outbox;
    if (o == null) {
      throw StateError(
          'OrdersRepository was constructed without an OutboxRepository; '
          'write methods are unavailable.');
    }
    return o;
  }

  OrdersCompanion _toCompanion(LaundryOrder order, String actorStaffId,
      {required DateTime now}) {
    return OrdersCompanion(
      id: Value(order.orderId),
      orderCode: Value(order.orderId),
      customerName: Value(order.customerName),
      phone: Value(order.phone),
      address: Value(order.address),
      serviceType: Value(order.serviceType),
      status: Value(order.status.toDbString()),
      // TODO(pr-b-new-pickup-form): intake_method/fulfillment_method are not
      // part of LaundryOrder yet; default to driver_pickup/delivery until the
      // New Pickup form (PR-B) adds them.
      intakeMethod: const Value('driver_pickup'),
      fulfillmentMethod: const Value('delivery'),
      itemCount: Value(order.itemCount),
      notes: Value(order.notes),
      intakeRecordedBy: Value(actorStaffId),
      createdBy: Value(actorStaffId),
      createdAt: Value(now),
      updatedAt: Value(now),
    );
  }

  Map<String, dynamic> _toPayload(LaundryOrder order, String actorStaffId,
      {required DateTime now}) =>
      {
        'id': order.orderId,
        'order_code': order.orderId,
        'customer_name': order.customerName,
        'phone': order.phone,
        'address': order.address,
        'service_type': order.serviceType,
        'status': order.status.toDbString(),
        // TODO(pr-b-new-pickup-form): see _toCompanion above.
        'intake_method': 'driver_pickup',
        'fulfillment_method': 'delivery',
        'item_count': order.itemCount,
        'notes': order.notes,
        'intake_recorded_by': actorStaffId,
        'created_by': actorStaffId,
        'created_at': now.toUtc().toIso8601String(),
        'updated_at': now.toUtc().toIso8601String(),
      };
}
