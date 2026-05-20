import 'package:drift/drift.dart';

import '../data/app_database.dart';

/// Read-side repository for proof events. Returns raw Drift `ProofEvent` rows
/// — the domain wrapper (`LaundryOrder.proofEvents`) is hydrated by
/// `OrdersRepository`, not here.
class ProofEventsRepository {
  ProofEventsRepository(this._db);

  final AppDatabase _db;

  /// Non-deleted proof events for [orderId], ordered by [ProofEvents.capturedAt].
  Stream<List<ProofEvent>> watchByOrder(String orderId) {
    return (_db.select(_db.proofEvents)
          ..where((t) => t.orderId.equals(orderId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm(expression: t.capturedAt)]))
        .watch();
  }
}
