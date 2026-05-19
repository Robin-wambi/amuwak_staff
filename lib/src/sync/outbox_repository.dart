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

  /// Record a failed dispatch attempt for [id]. Bumps `retry_count` and stores
  /// [error]. Once `retry_count > deadLetterAfter`, the row is flipped to
  /// `dead_letter` status, which excludes it from [peekPending] so a single
  /// permanently-failing row cannot head-of-line block the rest of the
  /// queue. Recovery from dead_letter is a separate manual / UI flow.
  Future<void> markFailed(String id, String error,
      {int deadLetterAfter = 5}) async {
    final row =
        await (_db.select(_db.outbox)..where((t) => t.id.equals(id)))
            .getSingleOrNull();
    if (row == null) return;
    final nextRetry = row.retryCount + 1;
    final newStatus = nextRetry > deadLetterAfter ? 'dead_letter' : 'failed';
    await (_db.update(_db.outbox)..where((t) => t.id.equals(id))).write(
      OutboxCompanion(
        retryCount: Value(nextRetry),
        lastError: Value(error),
        status: Value(newStatus),
        lastAttemptedAt: Value(DateTime.now()),
      ),
    );
  }
}
