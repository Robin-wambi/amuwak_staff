import 'package:drift/drift.dart';

import '../data/app_database.dart';

/// Read-side repository for staff users. Returns raw Drift `StaffData` rows.
class StaffRepository {
  StaffRepository(this._db);

  final AppDatabase _db;

  /// All non-deleted staff, sorted by [Staff.displayName].
  Stream<List<StaffData>> watchAll() {
    return (_db.select(_db.staff)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm(expression: t.displayName)]))
        .watch();
  }

  Stream<StaffData?> watchById(String id) {
    return (_db.select(_db.staff)..where((t) => t.id.equals(id)))
        .watchSingleOrNull();
  }
}
