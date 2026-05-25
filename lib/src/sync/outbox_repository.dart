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

  /// Builds a deterministic outbox key. Callers that may retry the same
  /// logical mutation (e.g. capture screens after a network blip) MUST pass
  /// the SAME key on retry — the outbox's [InsertMode.insertOrIgnore] then
  /// makes the second enqueue a SQL-level no-op.
  ///
  /// Format: `forTable:op:rowId[:extra]`. `extra` is typically the row's
  /// `updated_at` ISO string so that genuinely-distinct mutations to the
  /// same row (e.g. two successive status changes) get distinct keys.
  static String dedupKeyFor({
    required String forTable,
    required String op,
    required String rowId,
    String? extra,
  }) {
    return extra == null
        ? '$forTable:$op:$rowId'
        : '$forTable:$op:$rowId:$extra';
  }

  /// Enqueues a pending mutation, keyed by [id].
  ///
  /// Uses [InsertMode.insertOrIgnore] **intentionally**: callers MAY pass the
  /// same [id] across retries (e.g. capture screens that cache a mutation id
  /// in widget state so a partial-failure retry doesn't double-enqueue). On
  /// a duplicate id the insert silently no-ops at the SQL layer — the
  /// already-queued row remains intact with its earlier payload.
  ///
  /// Implication: callers MUST NOT mutate the payload between retries and
  /// then expect the new payload to land — only the first enqueue wins. If
  /// you need a different payload, use a different [id].
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

  /// Live stream of rows currently parked in `dead_letter`, newest-first.
  /// Drives the dashboard's sync-errors badge and the SyncErrorsScreen.
  Stream<List<OutboxData>> watchDeadLettered() {
    return (_db.select(_db.outbox)
          ..where((t) => t.status.equals('dead_letter'))
          ..orderBy([(t) => OrderingTerm.desc(t.lastAttemptedAt)]))
        .watch();
  }

  /// Resets a dead-lettered row back to `'pending'` so the outbox worker
  /// picks it up on its next drain.  Retry counter and last-error text are
  /// cleared so the user-visible counter starts fresh.
  Future<void> requeue(String id) {
    return (_db.update(_db.outbox)..where((t) => t.id.equals(id))).write(
      const OutboxCompanion(
        status: Value('pending'),
        retryCount: Value(0),
        lastError: Value(null),
        lastAttemptedAt: Value(null),
      ),
    );
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
