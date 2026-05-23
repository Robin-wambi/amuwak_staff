import 'package:drift/drift.dart';

import '../data/app_database.dart' as drift;
import '../orders/proof_event.dart';
import '../shared/uuid.dart';
import 'outbox_repository.dart';

/// Read/write repository for proof events.
///
/// Write methods ([insertEvent]) require an [OutboxRepository] to be supplied
/// at construction time. Callers that only need the read API can omit it;
/// attempting a write on a read-only-configured instance throws a [StateError].
class ProofEventsRepository {
  ProofEventsRepository(
    this._db, {
    OutboxRepository? outbox,
    DateTime Function()? clock,
    String Function()? uuid,
  })  : _outbox = outbox,
        _clock = clock ?? DateTime.now,
        _uuid = uuid ?? defaultUuidV4;

  final drift.AppDatabase _db;
  final OutboxRepository? _outbox;
  final DateTime Function() _clock;
  final String Function() _uuid;

  // ----- READ -----

  /// Non-deleted proof events for [orderId], ordered by [ProofEvents.capturedAt].
  Stream<List<drift.ProofEvent>> watchByOrder(String orderId) {
    return (_db.select(_db.proofEvents)
          ..where((t) => t.orderId.equals(orderId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm(expression: t.capturedAt)]))
        .watch();
  }

  // ----- WRITE -----

  /// Inserts a proof event row + an outbox enqueue inside a single
  /// transaction.
  ///
  /// Both inserts use `InsertMode.insertOrIgnore` so the operation is
  /// idempotent on the proof-event PK. This is load-bearing for capture-screen
  /// retries: if the inserts succeed but the caller's follow-up
  /// `OrdersRepository.updateStatus` throws, the user taps "Done" again with
  /// the SAME event id — the second insert here is a no-op rather than a
  /// duplicate-PK crash. The outbox enqueue already uses insertOrIgnore on the
  /// row's mutation id, so the retry's outbox write is idempotent too.
  Future<void> insertEvent(
    ProofEvent event, {
    required String orderId,
    required String actorStaffId,
  }) async {
    final outbox = _requireOutbox();
    final now = _clock();
    await _db.transaction(() async {
      await _db.into(_db.proofEvents).insert(
            drift.ProofEventsCompanion.insert(
              id: event.id,
              orderId: orderId,
              type: event.type.name,
              capturedAt: event.capturedAt,
              itemCount: event.count,
              notes: Value(event.notes),
              capturedBy: actorStaffId,
              createdAt: now,
              updatedAt: now,
            ),
            mode: InsertMode.insertOrIgnore,
          );
      await outbox.enqueue(
        id: _uuid(),
        forTable: 'proof_events',
        op: 'insert',
        rowId: event.id,
        payload: <String, dynamic>{
          'id': event.id,
          'order_id': orderId,
          'type': event.type.name,
          'captured_at': event.capturedAt.toUtc().toIso8601String(),
          'item_count': event.count,
          'notes': event.notes,
          'captured_by': actorStaffId,
          'created_at': now.toUtc().toIso8601String(),
          'updated_at': now.toUtc().toIso8601String(),
        },
      );
    });
  }

  // ----- PRIVATE HELPERS -----

  OutboxRepository _requireOutbox() {
    final o = _outbox;
    if (o == null) {
      throw StateError(
          'ProofEventsRepository was constructed without an OutboxRepository; '
          'insertEvent is unavailable.');
    }
    return o;
  }
}
