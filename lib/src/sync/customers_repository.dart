import 'package:drift/drift.dart';

import '../data/app_database.dart';

/// Read-side repository for customers. Returns raw Drift `Customer` rows —
/// no domain wrapper exists yet (and isn't needed until Plan 3b builds a
/// customer-detail screen that motivates one).
class CustomersRepository {
  CustomersRepository(this._db);

  final AppDatabase _db;

  /// All non-deleted customers, sorted by [Customers.name].
  Stream<List<Customer>> watchAll() {
    return (_db.select(_db.customers)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm(expression: t.name)]))
        .watch();
  }

  Stream<Customer?> watchById(String id) {
    return (_db.select(_db.customers)..where((t) => t.id.equals(id)))
        .watchSingleOrNull();
  }
}
