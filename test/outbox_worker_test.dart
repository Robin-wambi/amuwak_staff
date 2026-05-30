import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:amuwak_staff/src/data/app_database.dart';
import 'package:amuwak_staff/src/sync/outbox_repository.dart';
import 'package:amuwak_staff/src/sync/outbox_worker.dart';

class _DispatchRecorder {
  final List<List<dynamic>> calls = [];
  Object? throwThis;
  Completer<void>? blockOn;

  Future<void> dispatch(
    String forTable,
    String op,
    String rowId,
    Map<String, dynamic> payload,
  ) async {
    calls.add([forTable, op, rowId, payload]);
    if (blockOn != null) await blockOn!.future;
    if (throwThis != null) throw throwThis!;
  }
}

void main() {
  late AppDatabase db;
  late OutboxRepository repo;
  late _DispatchRecorder recorder;
  late OutboxWorker worker;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = OutboxRepository(db);
    recorder = _DispatchRecorder();
    worker = OutboxWorker(repo: repo, dispatch: recorder.dispatch);
  });

  tearDown(() async => db.close());

  test('drainOnce dispatches insert with the right (table, op, rowId, payload)',
      () async {
    await repo.enqueue(
      id: 'mut-1', forTable: 'orders', op: 'insert',
      rowId: 'order-1',
      payload: {'id': 'order-1', 'order_code': 'AMW-1'},
    );

    final drained = await worker.drainOnce();

    expect(drained, 1);
    expect(recorder.calls, hasLength(1));
    expect(recorder.calls.first, [
      'orders', 'insert', 'order-1',
      {'id': 'order-1', 'order_code': 'AMW-1'},
    ]);
    expect(await repo.peekPending(limit: 10), isEmpty,
        reason: 'successful row should be removed by markSent');
  });

  test('on PostgrestException, drainOnce marks failed and stops processing later rows',
      () async {
    recorder.throwThis = const PostgrestException(message: 'unique violation', code: '23505');

    await repo.enqueue(id: 'm1', forTable: 'orders', op: 'insert',
                       rowId: 'r1', payload: const {});
    await repo.enqueue(id: 'm2', forTable: 'orders', op: 'insert',
                       rowId: 'r2', payload: const {});

    final drained = await worker.drainOnce();

    expect(drained, 0);
    final pending = await repo.peekPending(limit: 10);
    expect(pending, hasLength(2));
    expect(pending.first.lastError, contains('23505'));
    expect(pending.first.lastError, contains('unique violation'));
    expect(pending.first.status, 'failed');
    expect(recorder.calls, hasLength(1),
        reason: 'second row should not be dispatched after first fails');
  });

  test('stop() awaits an in-flight drainOnce before returning', () async {
    // Block dispatch in flight so drainOnce can't complete on its own.
    final blocker = Completer<void>();
    recorder.blockOn = blocker;

    await repo.enqueue(
      id: 'm1', forTable: 'orders', op: 'insert',
      rowId: 'r1', payload: const {},
    );

    final draining = worker.drainOnce();
    // Let drainOnce reach the awaited dispatch.
    await Future<void>.delayed(Duration.zero);
    expect(recorder.calls, hasLength(1),
        reason: 'dispatch should have started');

    var stopDone = false;
    final stopFuture = worker.stop().whenComplete(() => stopDone = true);

    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(stopDone, isFalse,
        reason: 'stop should be waiting on the in-flight drain');

    // Release; both drain and stop should now finish.
    blocker.complete();
    await draining;
    await stopFuture;
    expect(stopDone, isTrue);
  });

  test('stop() is safe to call when no drain is in flight', () async {
    await expectLater(worker.stop(), completes);
  });

  test(
      'drainOnce is re-entrancy guarded: a concurrent call is a no-op and '
      'does not re-dispatch', () async {
    final blocker = Completer<void>();
    recorder.blockOn = blocker;

    await repo.enqueue(
      id: 'm1', forTable: 'orders', op: 'insert',
      rowId: 'r1', payload: const {},
    );

    // First call starts and blocks in dispatch.
    final first = worker.drainOnce();
    await Future<void>.delayed(Duration.zero);
    expect(recorder.calls, hasLength(1),
        reason: 'first drain should have dispatched one row');

    // Second call while first is in flight must be a no-op.
    final second = await worker.drainOnce();
    expect(second, 0,
        reason: 'concurrent drain should report nothing sent');
    expect(recorder.calls, hasLength(1),
        reason: 'concurrent drain must NOT trigger another dispatch');

    // Release; first completes normally.
    blocker.complete();
    expect(await first, 1);

    // After completion the guard clears: a fresh drain works normally.
    recorder.blockOn = null;
    await repo.enqueue(
      id: 'm2', forTable: 'orders', op: 'insert',
      rowId: 'r2', payload: const {},
    );
    expect(await worker.drainOnce(), 1);
    expect(recorder.calls, hasLength(2));
  });

  test(
      'transient (offline) errors do NOT dead-letter: row stays pending with '
      'retryCount 0 no matter how many drains run', () async {
    recorder.throwThis = SocketException('failed host lookup');

    await repo.enqueue(
      id: 'm1', forTable: 'orders', op: 'insert',
      rowId: 'r1', payload: const {},
    );

    // Far more drains than deadLetterAfter (5) — a real offline spell.
    for (var i = 0; i < 10; i++) {
      expect(await worker.drainOnce(), 0);
    }

    final pending = await repo.peekPending(limit: 10);
    expect(pending, hasLength(1),
        reason: 'the row must remain queued, not dead-lettered');
    expect(pending.first.status, 'pending',
        reason: 'offline blips must not flip status to failed/dead_letter');
    expect(pending.first.retryCount, 0,
        reason: 'transient errors must not burn the retry budget');
    expect(await repo.watchDeadLettered().first, isEmpty);
  });

  test('permanent (non-Postgrest) errors still dead-letter after the budget',
      () async {
    recorder.throwThis = StateError('OutboxWorker: unknown op "frobnicate"');

    await repo.enqueue(
      id: 'm1', forTable: 'orders', op: 'insert',
      rowId: 'r1', payload: const {},
    );

    for (var i = 0; i < 6; i++) {
      await worker.drainOnce();
    }

    expect(await repo.peekPending(limit: 10), isEmpty,
        reason: 'dead-lettered rows are excluded from peekPending');
    expect(await repo.watchDeadLettered().first, hasLength(1));
  });
}
