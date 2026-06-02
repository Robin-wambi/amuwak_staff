import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/app_database.dart';
import 'supabase_mappers.dart';

/// Read-side repository for staff users — ONLINE-ONLY mode. Streams `StaffData`
/// live from Supabase. The offline (local Drift) implementation is preserved in
/// the commented block at the bottom.
class StaffRepository {
  StaffRepository(this._supabase);

  final SupabaseClient _supabase;

  /// All non-deleted staff, sorted by display name.
  Stream<List<StaffData>> watchAll() {
    return _supabase
        .from('staff')
        .stream(primaryKey: ['id'])
        .order('display_name')
        .map((rows) => rows
            .where((r) => r['deleted_at'] == null)
            .map(staffFromSupabase)
            .toList(growable: false));
  }

  Stream<StaffData?> watchById(String id) {
    return _supabase
        .from('staff')
        .stream(primaryKey: ['id'])
        .eq('id', id)
        .map((rows) => rows.isEmpty ? null : staffFromSupabase(rows.first));
  }
}

/* ============================================================================
 * OFFLINE (local Drift reads) — PRESERVED FOR RE-ENABLE
 * ----------------------------------------------------------------------------
 * import 'package:drift/drift.dart';
 * import '../data/app_database.dart';
 *
 * class StaffRepository {
 *   StaffRepository(this._db);
 *   final AppDatabase _db;
 *
 *   Stream<List<StaffData>> watchAll() {
 *     return (_db.select(_db.staff)
 *           ..where((t) => t.deletedAt.isNull())
 *           ..orderBy([(t) => OrderingTerm(expression: t.displayName)])).watch();
 *   }
 *
 *   Stream<StaffData?> watchById(String id) {
 *     return (_db.select(_db.staff)..where((t) => t.id.equals(id)))
 *         .watchSingleOrNull();
 *   }
 * }
 * ========================================================================== */
