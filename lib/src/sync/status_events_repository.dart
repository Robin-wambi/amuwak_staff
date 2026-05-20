import 'package:drift/drift.dart';

import '../data/app_database.dart';

/// Read-side repository for the append-only `order_status_events` table.
/// Mutations belong on the outbox path (Plan 3b wires the capture screens
/// to enqueue inserts via `OutboxRepository`); intentionally no `update`,
/// `delete`, or `append` method exists here so callers can't bypass the
/// outbox.
class StatusEventsRepository {
  StatusEventsRepository(this._db);

  final AppDatabase _db;

  /// Status history for [orderId], ordered chronologically by `changed_at`.
  Stream<List<OrderStatusEvent>> watchByOrder(String orderId) {
    return (_db.select(_db.orderStatusEvents)
          ..where((t) => t.orderId.equals(orderId))
          ..orderBy([(t) => OrderingTerm(expression: t.changedAt)]))
        .watch();
  }
}
