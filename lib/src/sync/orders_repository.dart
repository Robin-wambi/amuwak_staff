import '../data/app_database.dart';
import '../orders/order.dart';

/// Read-side repository for orders.
///
/// Joined proof events are fetched via a follow-up query rather than a single
/// joined `.watch()` — Drift's joined streams emit flat rows that need
/// Dart-side grouping inside the stream reducer, which is fragile under
/// re-emission. Two simple queries are easier to reason about and the
/// performance cost (one extra `SELECT` per emission) is negligible for the
/// dashboard's order-list scale.
class OrdersRepository {
  OrdersRepository(this._db);

  final AppDatabase _db;

  Stream<List<LaundryOrder>> watchAll() {
    return _db.select(_db.orders).watch().asyncMap((rows) async {
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
    return (_db.select(_db.orders)..where((t) => t.id.equals(orderId)))
        .watchSingleOrNull()
        .asyncMap((row) async {
      if (row == null) return null;
      final events = await (_db.select(_db.proofEvents)
            ..where((t) => t.orderId.equals(orderId)))
          .get();
      return LaundryOrder.fromDriftRow(row, events);
    });
  }
}
