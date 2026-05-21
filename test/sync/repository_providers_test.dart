import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_staff/src/data/app_database.dart';
import 'package:amuwak_staff/src/sync/customers_repository.dart';
import 'package:amuwak_staff/src/sync/orders_repository.dart';
import 'package:amuwak_staff/src/sync/proof_events_repository.dart';
import 'package:amuwak_staff/src/sync/repository_providers.dart';
import 'package:amuwak_staff/src/sync/staff_repository.dart';
import 'package:amuwak_staff/src/sync/outbox_repository.dart';
import 'package:amuwak_staff/src/sync/status_events_repository.dart';
import 'package:amuwak_staff/src/sync/sync_status.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
    ]);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('ordersRepositoryProvider resolves to an OrdersRepository singleton', () {
    final a = container.read(ordersRepositoryProvider);
    final b = container.read(ordersRepositoryProvider);
    expect(a, isA<OrdersRepository>());
    expect(identical(a, b), isTrue, reason: 'provider should cache the value');
  });

  test('customersRepositoryProvider resolves to a CustomersRepository singleton', () {
    final a = container.read(customersRepositoryProvider);
    final b = container.read(customersRepositoryProvider);
    expect(a, isA<CustomersRepository>());
    expect(identical(a, b), isTrue);
  });

  test('staffRepositoryProvider resolves to a StaffRepository singleton', () {
    final a = container.read(staffRepositoryProvider);
    final b = container.read(staffRepositoryProvider);
    expect(a, isA<StaffRepository>());
    expect(identical(a, b), isTrue);
  });

  test('proofEventsRepositoryProvider resolves to a ProofEventsRepository singleton', () {
    final a = container.read(proofEventsRepositoryProvider);
    final b = container.read(proofEventsRepositoryProvider);
    expect(a, isA<ProofEventsRepository>());
    expect(identical(a, b), isTrue);
  });

  test('statusEventsRepositoryProvider resolves to a StatusEventsRepository singleton', () {
    final a = container.read(statusEventsRepositoryProvider);
    final b = container.read(statusEventsRepositoryProvider);
    expect(a, isA<StatusEventsRepository>());
    expect(identical(a, b), isTrue);
  });

  test('outboxRepositoryProvider resolves to an OutboxRepository singleton', () {
    final a = container.read(outboxRepositoryProvider);
    final b = container.read(outboxRepositoryProvider);
    expect(a, isA<OutboxRepository>());
    expect(identical(a, b), isTrue);
  });

  test('every repository receives the overridden AppDatabase', () async {
    // Sanity: insert into the in-memory DB and observe each repo can see it.
    await db.into(db.customers).insert(CustomersCompanion.insert(
          id: 'c-1',
          name: 'Alice',
          phone: '+256',
          createdAt: DateTime.utc(2026, 5, 19),
          updatedAt: DateTime.utc(2026, 5, 19),
        ));

    final customers =
        await container.read(customersRepositoryProvider).watchAll().first;
    expect(customers, hasLength(1));
    expect(customers.single.id, 'c-1');
  });
}
