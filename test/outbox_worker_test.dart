import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:amuwak_staff/src/data/app_database.dart';
import 'package:amuwak_staff/src/sync/outbox_repository.dart';
import 'package:amuwak_staff/src/sync/outbox_worker.dart';

class _DispatchRecorder {
  final List<List<dynamic>> calls = [];
  Object? throwThis;

  Future<void> dispatch(
    String forTable,
    String op,
    String rowId,
    Map<String, dynamic> payload,
  ) async {
    calls.add([forTable, op, rowId, payload]);
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
}
