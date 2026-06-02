import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/app_database.dart' as drift;
import '../orders/proof_event.dart';
import 'supabase_mappers.dart';

/// Read/write repository for proof events — ONLINE-ONLY mode.
///
/// Reads stream live from Supabase; [insertEvent] upserts directly (upsert,
/// not insert, so capture-screen retries with the same event id are
/// idempotent rather than duplicate-PK crashes — the same retry safety the
/// offline `insertOrIgnore` gave). The offline-first implementation is
/// preserved in the commented `OFFLINE` block at the bottom of this file.
class ProofEventsRepository {
  ProofEventsRepository(
    this._supabase, {
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final SupabaseClient _supabase;
  final DateTime Function() _clock;

  // ----- READ -----

  /// Non-deleted proof events for [orderId], ordered by `captured_at`.
  Stream<List<drift.ProofEvent>> watchByOrder(String orderId) {
    return _supabase
        .from('proof_events')
        .stream(primaryKey: ['id'])
        .eq('order_id', orderId)
        .order('captured_at')
        .map((rows) => rows
            .where((r) => r['deleted_at'] == null)
            .map(proofEventRowFromSupabase)
            .toList(growable: false));
  }

  // ----- WRITE -----

  /// Upserts a proof event. Idempotent on the proof-event PK so a capture
  /// screen that retries (e.g. after the follow-up status update throws) with
  /// the SAME event id is a no-op rather than a duplicate-key error.
  Future<void> insertEvent(
    ProofEvent event, {
    required String orderId,
    required String actorStaffId,
  }) async {
    final now = _clock();
    await _supabase.from('proof_events').upsert(<String, dynamic>{
      'id': event.id,
      'order_id': orderId,
      'type': event.type.name,
      'captured_at': event.capturedAt.toUtc().toIso8601String(),
      'item_count': event.count,
      'notes': event.notes,
      'captured_by': actorStaffId,
      'created_at': now.toUtc().toIso8601String(),
      'updated_at': now.toUtc().toIso8601String(),
    });
  }
}

/* ============================================================================
 * OFFLINE (Drift local reads + outbox-queued writes) — PRESERVED FOR RE-ENABLE
 * ----------------------------------------------------------------------------
 * import 'package:drift/drift.dart';
 * import '../data/app_database.dart' as drift;
 * import '../orders/proof_event.dart';
 * import 'outbox_repository.dart';
 *
 * class ProofEventsRepository {
 *   ProofEventsRepository(this._db, {OutboxRepository? outbox, DateTime Function()? clock})
 *       : _outbox = outbox, _clock = clock ?? DateTime.now;
 *   final drift.AppDatabase _db;
 *   final OutboxRepository? _outbox;
 *   final DateTime Function() _clock;
 *
 *   Stream<List<drift.ProofEvent>> watchByOrder(String orderId) {
 *     return (_db.select(_db.proofEvents)
 *           ..where((t) => t.orderId.equals(orderId) & t.deletedAt.isNull())
 *           ..orderBy([(t) => OrderingTerm(expression: t.capturedAt)])).watch();
 *   }
 *
 *   Future<void> insertEvent(ProofEvent event,
 *       {required String orderId, required String actorStaffId}) async {
 *     final outbox = _requireOutbox();
 *     final now = _clock();
 *     await _db.transaction(() async {
 *       await _db.into(_db.proofEvents).insert(
 *             drift.ProofEventsCompanion.insert(
 *               id: event.id, orderId: orderId, type: event.type.name,
 *               capturedAt: event.capturedAt, itemCount: event.count,
 *               notes: Value(event.notes), capturedBy: actorStaffId,
 *               createdAt: now, updatedAt: now),
 *             mode: InsertMode.insertOrIgnore);
 *       await outbox.enqueue(
 *         id: OutboxRepository.dedupKeyFor(
 *           forTable: 'proof_events', op: 'insert', rowId: event.id),
 *         forTable: 'proof_events', op: 'insert', rowId: event.id,
 *         payload: <String, dynamic>{
 *           'id': event.id, 'order_id': orderId, 'type': event.type.name,
 *           'captured_at': event.capturedAt.toUtc().toIso8601String(),
 *           'item_count': event.count, 'notes': event.notes,
 *           'captured_by': actorStaffId,
 *           'created_at': now.toUtc().toIso8601String(),
 *           'updated_at': now.toUtc().toIso8601String()});
 *     });
 *   }
 *
 *   OutboxRepository _requireOutbox() {
 *     final o = _outbox;
 *     if (o == null) {
 *       throw StateError('ProofEventsRepository was constructed without an '
 *           'OutboxRepository; insertEvent is unavailable.');
 *     }
 *     return o;
 *   }
 * }
 * ========================================================================== */
