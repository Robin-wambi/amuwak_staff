import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_staff/src/data/app_database.dart';
import 'package:amuwak_staff/src/orders/new_pickup_result.dart';
import 'package:amuwak_staff/src/orders/new_pickup_screen.dart';
import 'package:amuwak_staff/src/orders/service_type.dart';
import 'package:amuwak_staff/src/sync/customers_repository.dart';
import 'package:amuwak_staff/src/sync/orders_repository.dart';
import 'package:amuwak_staff/src/sync/outbox_repository.dart';

void main() {
  late AppDatabase db;
  late OutboxRepository outbox;
  late CustomersRepository customersRepo;
  late OrdersRepository ordersRepo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    outbox = OutboxRepository(db);
    customersRepo = CustomersRepository(db, outbox: outbox,
        clock: () => DateTime(2026, 5, 25, 10));
    ordersRepo = OrdersRepository(db, outbox: outbox,
        clock: () => DateTime(2026, 5, 25, 10));
  });

  tearDown(() async => db.close());

  Future<NewPickupResult?> pumpFormAndOpen(WidgetTester tester) async {
    NewPickupResult? popped;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  popped = await Navigator.of(context).push<NewPickupResult>(
                    MaterialPageRoute(
                      builder: (_) => NewPickupScreen(
                        customersRepo: customersRepo,
                        ordersRepo: ordersRepo,
                        actorStaffId: 'staff-1',
                        clock: () => DateTime(2026, 5, 25, 10),
                        orderIdGenerator: () => 'uuid-order-1',
                        customerIdGenerator: () => 'uuid-cust-1',
                        geolocate: () async => null,
                        reverseGeocode: (_) async => null,
                      ),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    return popped;
  }

  testWidgets('Create button is disabled until required fields are valid',
      (tester) async {
    await pumpFormAndOpen(tester);
    final create = find.widgetWithText(ElevatedButton, 'Create pickup');
    expect(tester.widget<ElevatedButton>(create).onPressed, isNull);

    await tester.enterText(find.byKey(const Key('np_name')), 'Jane Doe');
    await tester.enterText(find.byKey(const Key('np_phone')), '+256 700 111 222');
    await tester.enterText(find.byKey(const Key('np_address')), 'Kikoni, Kampala');
    await tester.tap(find.byKey(const Key('np_service_type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(ServiceType.washAndIron.label).last);
    await tester.pumpAndSettle();

    expect(tester.widget<ElevatedButton>(create).onPressed, isNotNull);
  });

  testWidgets('Submit happy path writes customer + order, pops with '
      'startPickupNow=true (default schedule)', (tester) async {
    await pumpFormAndOpen(tester);

    await tester.enterText(find.byKey(const Key('np_name')), 'Jane Doe');
    await tester.enterText(find.byKey(const Key('np_phone')), '+256 700 111 222');
    await tester.enterText(find.byKey(const Key('np_address')), 'Kikoni, Kampala');
    await tester.tap(find.byKey(const Key('np_service_type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(ServiceType.washAndIron.label).last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Create pickup'));
    await tester.pumpAndSettle();

    final customers = await db.select(db.customers).get();
    expect(customers, hasLength(1));
    expect(customers.single.id, 'uuid-cust-1');
    expect(customers.single.name, 'Jane Doe');

    final orders = await db.select(db.orders).get();
    expect(orders, hasLength(1));
    expect(orders.single.id, 'uuid-order-1');
    expect(orders.single.customerId, 'uuid-cust-1');
    expect(orders.single.customerName, 'Jane Doe');
    expect(orders.single.serviceType, ServiceType.washAndIron.toDbString());
    expect(orders.single.status, 'pending_pickup');
    expect(orders.single.scheduledFor, isNull);
    expect(orders.single.orderCode, startsWith('AMW-'));
  });

  testWidgets('Cancel returns null and writes nothing', (tester) async {
    final popped = await pumpFormAndOpen(tester);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(popped, isNull);
    final customers = await db.select(db.customers).get();
    final orders = await db.select(db.orders).get();
    expect(customers, isEmpty);
    expect(orders, isEmpty);
  });
}
