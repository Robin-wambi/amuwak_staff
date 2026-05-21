import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:amuwak_staff/src/data/app_database.dart' as drift;
import 'package:amuwak_staff/src/orders/proof_event.dart';
import 'package:amuwak_staff/src/sync/outbox_repository.dart';
import 'package:amuwak_staff/src/sync/proof_events_repository.dart';

DateTime fixedClock() => DateTime.utc(2026, 5, 21, 12);

void main() {
  late drift.AppDatabase db;
  late OutboxRepository outbox;
  late ProofEventsRepository repo;
  var seq = 0;

  setUp(() {
    db = drift.AppDatabase.forTesting(NativeDatabase.memory());
    outbox = OutboxRepository(db);
    seq = 0;
    repo = ProofEventsRepository(
      db,
      outbox: outbox,
      clock: fixedClock,
      uuid: () => 'mut-${++seq}',
    );
  });
  tearDown(() async => db.close());

  test('insertEvent writes the row and enqueues one outbox insert', () async {
    final event = ProofEvent(
      id: 'pe-1',
      type: ProofEventType.pickup,
      capturedAt: DateTime.utc(2026, 5, 21, 10, 30),
      count: 3,
      photoPaths: const [],
      notes: 'Bagged carefully',
    );

    await repo.insertEvent(event, orderId: 'AMW-A', actorStaffId: 's-1');

    final rows = await db.select(db.proofEvents).get();
    expect(rows, hasLength(1));
    expect(rows.single.id, 'pe-1');
    expect(rows.single.orderId, 'AMW-A');
    expect(rows.single.type, 'pickup');
    expect(rows.single.capturedBy, 's-1');
    expect(rows.single.itemCount, 3);
    expect(rows.single.notes, 'Bagged carefully');

    final outboxRows = await db.select(db.outbox).get();
    expect(outboxRows, hasLength(1));
    expect(outboxRows.single.forTable, 'proof_events');
    expect(outboxRows.single.op, 'insert');
    expect(outboxRows.single.rowId, 'pe-1');
    expect(outboxRows.single.id, 'mut-1');
    final payload = jsonDecode(outboxRows.single.payloadJson) as Map;
    expect(payload['id'], 'pe-1');
    expect(payload['order_id'], 'AMW-A');
    expect(payload['type'], 'pickup');
    expect(payload['item_count'], 3);
    expect(payload['notes'], 'Bagged carefully');
    expect(payload['captured_by'], 's-1');
    expect(payload['captured_at'], '2026-05-21T10:30:00.000Z');
    expect(payload['created_at'], '2026-05-21T12:00:00.000Z');
    expect(payload['updated_at'], '2026-05-21T12:00:00.000Z');
  });

  test('insertEvent passes null notes through cleanly', () async {
    final event = ProofEvent(
      id: 'pe-2',
      type: ProofEventType.delivery,
      capturedAt: DateTime.utc(2026, 5, 21, 16),
      count: 2,
      photoPaths: const [],
      // notes omitted
    );

    await repo.insertEvent(event, orderId: 'AMW-B', actorStaffId: 's-1');

    final rows = await db.select(db.proofEvents).get();
    expect(rows.single.notes, isNull);
    final outboxRows = await db.select(db.outbox).get();
    final payload = jsonDecode(outboxRows.single.payloadJson) as Map;
    expect(payload['notes'], isNull);
  });

  test('insertEvent throws StateError when no outbox is wired', () async {
    final readOnlyRepo = ProofEventsRepository(db); // no outbox
    final event = ProofEvent(
      id: 'pe-x',
      type: ProofEventType.pickup,
      capturedAt: DateTime.utc(2026, 5, 21),
      count: 1,
      photoPaths: const [],
    );

    await expectLater(
      () => readOnlyRepo.insertEvent(event, orderId: 'AMW-X', actorStaffId: 's-1'),
      throwsA(isA<StateError>()),
    );

    final rows = await db.select(db.proofEvents).get();
    expect(rows, isEmpty);
  });
}
