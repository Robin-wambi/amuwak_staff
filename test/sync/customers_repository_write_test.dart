import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_staff/src/data/app_database.dart';
import 'package:amuwak_staff/src/sync/customers_repository.dart';
import 'package:amuwak_staff/src/sync/outbox_repository.dart';

void main() {
  late AppDatabase db;
  late OutboxRepository outbox;
  late CustomersRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    outbox = OutboxRepository(db);
    repo = CustomersRepository(db, outbox: outbox, clock: () => DateTime(2026, 5, 25, 10));
  });

  tearDown(() async => db.close());

  test('upsertCustomer writes the customer row + an outbox enqueue', () async {
    final customer = Customer(
      id: 'cust-1',
      name: 'Jane Doe',
      phone: '+256 700 111 222',
      address: 'Kikoni',
      notes: null,
      createdAt: DateTime(2026, 5, 25, 10),
      updatedAt: DateTime(2026, 5, 25, 10),
      deletedAt: null,
    );

    await repo.upsertCustomer(customer);

    final row = await (db.select(db.customers)
          ..where((t) => t.id.equals('cust-1')))
        .getSingle();
    expect(row.name, 'Jane Doe');
    expect(row.phone, '+256 700 111 222');
    expect(row.address, 'Kikoni');

    final outboxRows = await db.select(db.outbox).get();
    expect(outboxRows, hasLength(1));
    expect(outboxRows.single.forTable, 'customers');
    expect(outboxRows.single.op, 'insert');
    expect(outboxRows.single.rowId, 'cust-1');
  });

  test('upsertCustomer is idempotent on the same id within the same clock tick',
      () async {
    final customer = Customer(
      id: 'cust-2',
      name: 'Jane Doe',
      phone: '+256 700 111 222',
      address: 'Kikoni',
      notes: null,
      createdAt: DateTime(2026, 5, 25, 10),
      updatedAt: DateTime(2026, 5, 25, 10),
      deletedAt: null,
    );

    await repo.upsertCustomer(customer);
    await repo.upsertCustomer(customer);

    final rows = await db.select(db.customers).get();
    expect(rows, hasLength(1));
    final outboxRows = await db.select(db.outbox).get();
    expect(outboxRows, hasLength(1));
  });

  test('upsertCustomer throws StateError if constructed without outbox',
      () async {
    final readOnly = CustomersRepository(db);
    expect(
      () => readOnly.upsertCustomer(Customer(
        id: 'cust-3',
        name: 'X',
        phone: 'X',
        address: null,
        notes: null,
        createdAt: DateTime(2026, 5, 25, 10),
        updatedAt: DateTime(2026, 5, 25, 10),
        deletedAt: null,
      )),
      throwsA(isA<StateError>()),
    );
  });
}
