import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/app_database.dart' as drift;
import '../orders/proof_event.dart';
import 'supabase_mappers.dart';
import 'supabase_payloads.dart';

/// Test seam for the proof-event upsert: given the column map, returns the
/// "selected" rows (empty ⇒ the write did not persist). Lets unit tests
/// exercise [ProofEventsRepository.insertEvent]'s payload + missing-write
/// [StateError] without a live SupabaseClient.
typedef ProofEventUpsert =
    Future<List<Map<String, dynamic>>> Function(Map<String, dynamic> values);

/// Read/write repository for proof events — ONLINE-ONLY mode.
///
/// Reads stream live from Supabase; [insertEvent] upserts directly (upsert,
/// not insert, so capture-screen retries with the same event id are
/// idempotent rather than duplicate-PK crashes — the same retry safety the
/// offline `insertOrIgnore` gave). The offline-first implementation is
/// preserved in the commented `OFFLINE` block at the bottom of this file.
class ProofEventsRepository {
  ProofEventsRepository(
    SupabaseClient supabase, {
    DateTime Function()? clock,
  })  : _supabase = supabase,
        _clock = clock ?? DateTime.now,
        _upsertOverride = null;

  /// Test seam: inject the raw `upsert(...).select('id')` so unit tests can
  /// drive [insertEvent] (payload shape + missing-write [StateError]) without
  /// mocking SupabaseClient. The read stream is unavailable on a forTest
  /// instance (it asserts the client is present).
  ProofEventsRepository.forTest({
    required DateTime Function() clock,
    ProofEventUpsert? upsertRow,
  })  : _supabase = null,
        _clock = clock,
        _upsertOverride = upsertRow;

  final SupabaseClient? _supabase;
  final DateTime Function() _clock;
  final ProofEventUpsert? _upsertOverride;

  /// Dispatches the proof-event upsert and returns the selected rows so the
  /// caller can detect a write that didn't persist (empty ⇒ nothing written).
  /// Routes through the test override when constructed via [forTest], else the
  /// live Supabase client.
  Future<List<Map<String, dynamic>>> _upsertRow(
      Map<String, dynamic> values) async {
    final override = _upsertOverride;
    if (override != null) return override(values);
    assert(_supabase != null,
        'forTest instance has no upsertRow — '
        'pass one to ProofEventsRepository.forTest(upsertRow: ...)');
    return _supabase!.from('proof_events').upsert(values).select('id');
  }

  // ----- READ -----

  /// Non-deleted proof events for [orderId], ordered by `captured_at`.
  Stream<List<drift.ProofEvent>> watchByOrder(String orderId) {
    return _supabase!
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
  ///
  /// Throws a [StateError] when the upsert wrote no row (e.g. an RLS policy
  /// silently dropped it) so a captured photo/proof never shows "saved" for a
  /// write that didn't persist — the `.select('id')` returning empty is the
  /// signal.
  Future<void> insertEvent(
    ProofEvent event, {
    required String orderId,
    required String actorStaffId,
  }) async {
    final now = _clock();
    final written = await _upsertRow(proofEventUpsertPayload(
          event,
          orderId: orderId,
          actorStaffId: actorStaffId,
          now: now,
        ));
    if (written.isEmpty) {
      throw StateError(
          'insertEvent: write did not persist proof event "${event.id}"');
    }
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
