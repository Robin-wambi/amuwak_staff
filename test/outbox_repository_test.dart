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
}
