import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:amuwak_staff/src/data/app_database.dart';
import 'package:amuwak_staff/src/sync/outbox_repository.dart';

void main() {
  late AppDatabase db;
  late OutboxRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = OutboxRepository(db);
  });

  tearDown(() async => db.close());

  test('enqueue stores a pending row visible to peekPending', () async {
    await repo.enqueue(
      id: 'mut-1',
      forTable: 'orders',
      op: 'insert',
      rowId: 'order-1',
      payload: {'id': 'order-1', 'order_code': 'AMW-1'},
    );
    final pending = await repo.peekPending(limit: 10);
    expect(pending, hasLength(1));
    expect(pending.first.id, 'mut-1');
    expect(pending.first.forTable, 'orders');
    expect(pending.first.status, 'pending');
  });

  test('markSent removes the row', () async {
    await repo.enqueue(
      id: 'mut-2', forTable: 'orders', op: 'insert',
      rowId: 'order-2', payload: const {},
    );
    await repo.markSent('mut-2');
    expect(await repo.peekPending(limit: 10), isEmpty);
  });

  test('markFailed increments retry_count, records the error, and keeps the row visible',
      () async {
    await repo.enqueue(
      id: 'mut-3', forTable: 'orders', op: 'insert',
      rowId: 'order-3', payload: const {},
    );
    await repo.markFailed('mut-3', 'network timeout');
    final rows = await repo.peekPending(limit: 10);
    expect(rows, hasLength(1));
    expect(rows.first.retryCount, 1);
    expect(rows.first.lastError, 'network timeout');
    expect(rows.first.status, 'failed');
  });

  test('concurrent markFailed calls do not lose retry increments', () async {
    await repo.enqueue(
      id: 'race', forTable: 'orders', op: 'insert',
      rowId: 'r', payload: const {},
    );
    // Fire several failures concurrently. A non-atomic read-modify-write would
    // let each call read the same retry_count and clobber the others' writes,
    // landing well below 5. An atomic increment must reach exactly 5.
    await Future.wait([
      for (var i = 0; i < 5; i++)
        repo.markFailed('race', 'boom $i', deadLetterAfter: 100),
    ]);
    final row =
        await (db.select(db.outbox)..where((t) => t.id.equals('race')))
            .getSingle();
    expect(row.retryCount, 5);
    expect(row.status, 'failed');
  });

  group('dead-letter surface (Plan 4 Task 4)', () {
    test('watchDeadLettered emits rows in dead_letter status', () async {
      await repo.enqueue(
        id: 'k-pending', forTable: 'orders', op: 'update', rowId: 'A',
        payload: const {},
      );
      await repo.enqueue(
        id: 'k-failed', forTable: 'orders', op: 'update', rowId: 'B',
        payload: const {},
      );
      // Push k-failed into dead_letter by failing 6 times.
      for (var i = 0; i < 6; i++) {
        await repo.markFailed('k-failed', 'boom $i');
      }

      final dead = await repo.watchDeadLettered().first;
      expect(dead.map((r) => r.id).toList(), ['k-failed']);
    });

    test('requeue resets retry_count + flips status back to pending',
        () async {
      await repo.enqueue(
        id: 'k-stuck', forTable: 'orders', op: 'update', rowId: 'A',
        payload: const {},
      );
      for (var i = 0; i < 6; i++) {
        await repo.markFailed('k-stuck', 'boom');
      }

      await repo.requeue('k-stuck');

      final row =
          await (db.select(db.outbox)..where((t) => t.id.equals('k-stuck')))
              .getSingle();
      expect(row.status, 'pending');
      expect(row.retryCount, 0);
      expect(row.lastError, isNull);
      // peekPending should now include it.
      final pending = await repo.peekPending(limit: 10);
      expect(pending.map((r) => r.id), contains('k-stuck'));
    });

    test('requeue leaves a still-failed (not dead-lettered) row untouched',
        () async {
      await repo.enqueue(
        id: 'k-failed', forTable: 'orders', op: 'update', rowId: 'A',
        payload: const {},
      );
      // One failure → status 'failed', retryCount 1, but NOT dead-lettered.
      await repo.markFailed('k-failed', 'boom');

      // A stale reference must not reset the retry counter on this row.
      await repo.requeue('k-failed');

      final row =
          await (db.select(db.outbox)..where((t) => t.id.equals('k-failed')))
              .getSingle();
      expect(row.status, 'failed',
          reason: 'requeue must only act on dead_letter rows');
      expect(row.retryCount, 1,
          reason: 'requeue must not reset the budget on a non-dead row');
    });
  });

  test('discard permanently removes a dead-lettered row from the queue',
      () async {
    await repo.enqueue(
      id: 'm1', forTable: 'orders', op: 'update',
      rowId: 'r1', payload: const {},
    );
    for (var i = 0; i < 6; i++) {
      await repo.markFailed('m1', 'boom');
    }
    expect(await repo.watchDeadLettered().first, hasLength(1),
        reason: 'row should be dead-lettered after exceeding the budget');

    await repo.discard('m1');

    expect(await repo.watchDeadLettered().first, isEmpty);
    expect(await repo.peekPending(limit: 10), isEmpty);
  });

  test('discard leaves a still-pending row untouched', () async {
    await repo.enqueue(
      id: 'p1', forTable: 'orders', op: 'update',
      rowId: 'r1', payload: const {},
    );

    // A stale reference to a row that has NOT dead-lettered must not delete it.
    await repo.discard('p1');

    expect(await repo.peekPending(limit: 10), hasLength(1),
        reason: 'discard must only drop dead-lettered rows, not pending ones');
  });

  group('dedupKeyFor (Plan 4 Task 2)', () {
    test('produces a stable string from (forTable, op, rowId, extra)', () {
      expect(
        OutboxRepository.dedupKeyFor(
          forTable: 'orders',
          op: 'update',
          rowId: 'AMW-A',
          extra: '2026-05-23T12:00:00.000Z',
        ),
        'orders:update:AMW-A:2026-05-23T12:00:00.000Z',
      );
    });

    test('omits the trailing segment when extra is absent', () {
      expect(
        OutboxRepository.dedupKeyFor(
          forTable: 'proof_events',
          op: 'insert',
          rowId: 'pe-42',
        ),
        'proof_events:insert:pe-42',
      );
    });

    test('two enqueue calls with the same dedupKey produce one outbox row',
        () async {
      final key = OutboxRepository.dedupKeyFor(
        forTable: 'orders',
        op: 'update',
        rowId: 'AMW-A',
        extra: '2026-05-23T12:00:00.000Z',
      );
      await repo.enqueue(
        id: key, forTable: 'orders', op: 'update', rowId: 'AMW-A',
        payload: const <String, dynamic>{'status': 'ready'},
      );
      await repo.enqueue(
        id: key, forTable: 'orders', op: 'update', rowId: 'AMW-A',
        payload: const <String, dynamic>{'status': 'ready'},
      );

      final rows = await db.select(db.outbox).get();
      expect(rows, hasLength(1));
    });
  });
}
