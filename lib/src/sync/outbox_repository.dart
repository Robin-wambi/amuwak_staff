import 'dart:convert';
import 'package:drift/drift.dart';
import '../data/app_database.dart';

/// Wraps the local `outbox` Drift table. Callers enqueue pending mutations;
/// the OutboxWorker drains them via Supabase.
///
/// The Drift column for the target table name is `forTable` (rather than
/// `tableName`) because Drift's Table base class already exposes a
/// `tableName` getter. We carry that naming through this repository too.
class OutboxRepository {
  OutboxRepository(this._db);
  final AppDatabase _db;

  Future<void> enqueue({
    required String id,
    required String forTable,
    required String op,                // 'insert' | 'update' | 'delete'
    required String rowId,
    required Map<String, dynamic> payload,
  }) {
    return _db.into(_db.outbox).insert(
          OutboxCompanion.insert(
            id: id,
            forTable: forTable,
            op: op,
            rowId: rowId,
            payloadJson: jsonEncode(payload),
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  Future<List<OutboxData>> peekPending({required int limit}) {
    final query = _db.select(_db.outbox)
      ..where((t) => t.status.isIn(<String>['pending', 'failed']))
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt)])
      ..limit(limit);
    return query.get();
  }

  Future<void> markSent(String id) {
    return (_db.delete(_db.outbox)..where((t) => t.id.equals(id))).go();
  }

  Future<void> markFailed(String id, String error) async {
    // Drift companions can't reference current values, so increment via
    // raw SQL after writing the status/error fields.
    await (_db.update(_db.outbox)..where((t) => t.id.equals(id))).write(
      OutboxCompanion(
        lastError: Value(error),
        status: const Value('failed'),
        lastAttemptedAt: Value(DateTime.now()),
      ),
    );
    await _db.customUpdate(
      'UPDATE outbox SET retry_count = retry_count + 1 WHERE id = ?',
      variables: [Variable.withString(id)],
      updates: {_db.outbox},
    );
  }
}
