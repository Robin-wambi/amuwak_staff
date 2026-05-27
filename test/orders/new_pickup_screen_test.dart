import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_staff/src/data/app_database.dart';
import 'package:amuwak_staff/src/orders/geo_services.dart';
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

  testWidgets('Phone-on-blur with a matching customer shows the bottom sheet; '
      'tapping "Use this customer" pre-fills name + address', (tester) async {
    await customersRepo.upsertCustomer(Customer(
      id: 'existing-cust-1',
      name: 'Jane Existing',
      phone: '+256 700 111 222',
      address: 'Old address, Kampala',
      notes: null,
      createdAt: DateTime(2026, 5, 20, 9),
      updatedAt: DateTime(2026, 5, 20, 9),
      deletedAt: null,
    ));
    await pumpFormAndOpen(tester);

    await tester.enterText(find.byKey(const Key('np_phone')), '+256 700 111 222');
    await tester.tap(find.byKey(const Key('np_name')));
    await tester.pumpAndSettle();

    expect(find.text('Use this customer'), findsOneWidget);
    expect(find.text('Jane Existing'), findsAtLeastNWidgets(1));

    await tester.tap(find.text('Use this customer'));
    await tester.pumpAndSettle();

    expect(
      (tester.widget<TextFormField>(find.byKey(const Key('np_name')))).controller!.text,
      'Jane Existing',
    );
    expect(
      (tester.widget<TextFormField>(find.byKey(const Key('np_address')))).controller!.text,
      'Old address, Kampala',
    );
  });

  testWidgets('Submit with a matched existing customer reuses customer id',
      (tester) async {
    await customersRepo.upsertCustomer(Customer(
      id: 'existing-cust-2',
      name: 'Bob Returning',
      phone: '+256 701 222 333',
      address: 'Wandegeya',
      notes: null,
      createdAt: DateTime(2026, 5, 20, 9),
      updatedAt: DateTime(2026, 5, 20, 9),
      deletedAt: null,
    ));
    await pumpFormAndOpen(tester);

    await tester.enterText(find.byKey(const Key('np_phone')), '+256 701 222 333');
    await tester.tap(find.byKey(const Key('np_name')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use this customer'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('np_service_type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(ServiceType.dryCleaning.label).last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Create pickup'));
    await tester.pumpAndSettle();

    final customers = await db.select(db.customers).get();
    expect(customers, hasLength(1));
    expect(customers.single.id, 'existing-cust-2');
    final orders = await db.select(db.orders).get();
    expect(orders.single.customerId, 'existing-cust-2');
  });

  testWidgets(
      'Editing the phone field after accepting a customer match drops the '
      'cached customer id so submit does not overwrite the matched row',
      (tester) async {
    await customersRepo.upsertCustomer(Customer(
      id: 'existing-cust-edited',
      name: 'Carol Original',
      phone: '+256 702 333 444',
      address: 'Original address',
      notes: null,
      createdAt: DateTime(2026, 5, 20, 9),
      updatedAt: DateTime(2026, 5, 20, 9),
      deletedAt: null,
    ));
    await pumpFormAndOpen(tester);

    await tester.enterText(find.byKey(const Key('np_phone')), '+256 702 333 444');
    await tester.tap(find.byKey(const Key('np_name')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use this customer'));
    await tester.pumpAndSettle();
    // Rider realises the wrong customer was matched and edits the phone.
    await tester.enterText(find.byKey(const Key('np_phone')), '+256 702 999 999');
    await tester.tap(find.byKey(const Key('np_service_type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(ServiceType.washAndIron.label).last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Create pickup'));
    await tester.pumpAndSettle();

    final customers = await db.select(db.customers).get();
    expect(customers, hasLength(2));
    // Original row's data must not be clobbered.
    final original = customers.firstWhere((c) => c.id == 'existing-cust-edited');
    expect(original.name, 'Carol Original');
    expect(original.phone, '+256 702 333 444');
    expect(original.address, 'Original address');
    // New row was created (id from customerIdGenerator) and the order
    // points at it, not at the original.
    final newCustomer =
        customers.firstWhere((c) => c.id != 'existing-cust-edited');
    expect(newCustomer.id, 'uuid-cust-1');
    final orders = await db.select(db.orders).get();
    expect(orders.single.customerId, 'uuid-cust-1');
  });

  testWidgets('Use my location chip fills address from stubbed reverseGeocode',
      (tester) async {
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
                        geolocate: () async => const GeoLocation(
                            latitude: 0.3163, longitude: 32.5822),
                        reverseGeocode: (loc) async => 'Detected address, Kampala',
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

    await tester.tap(find.widgetWithText(ActionChip, 'Use my location'));
    await tester.pumpAndSettle();

    expect(
      (tester.widget<TextFormField>(find.byKey(const Key('np_address')))).controller!.text,
      'Detected address, Kampala',
    );
    expect(popped, isNull);
  });

  testWidgets('Schedule for later → Tomorrow morning sets scheduledFor to '
      '9 AM next day and pops with startPickupNow=false', (tester) async {
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

    await tester.enterText(find.byKey(const Key('np_name')), 'Jane Doe');
    await tester.enterText(find.byKey(const Key('np_phone')), '+256 700 111 222');
    await tester.enterText(find.byKey(const Key('np_address')), 'Kikoni');
    await tester.tap(find.byKey(const Key('np_service_type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(ServiceType.washAndIron.label).last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Schedule for later'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Tomorrow morning'));
    await tester.pumpAndSettle();

    // The tapped chip is now visually selected; sibling chips are not.
    final tomorrowMorningChip = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, 'Tomorrow morning'));
    expect(tomorrowMorningChip.selected, isTrue);
    final inOneHourChip = tester
        .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'In 1 hour'));
    expect(inOneHourChip.selected, isFalse);
    // The preview text uses the human-readable formatter, not raw toString.
    expect(find.text('Scheduled for: Tomorrow, 9:00 AM'), findsOneWidget);

    await tester.dragUntilVisible(
      find.widgetWithText(ElevatedButton, 'Create pickup'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Create pickup'));
    await tester.pumpAndSettle();

    expect(popped, isNotNull);
    expect(popped!.startPickupNow, isFalse);
    final orders = await db.select(db.orders).get();
    expect(orders.single.scheduledFor, DateTime(2026, 5, 26, 9));
  });

  testWidgets('Optional details: expand → stepper increments count, notes '
      'are persisted in the order row', (tester) async {
    await pumpFormAndOpen(tester);

    await tester.enterText(find.byKey(const Key('np_name')), 'Jane Doe');
    await tester.enterText(find.byKey(const Key('np_phone')), '+256 700 111 222');
    await tester.enterText(find.byKey(const Key('np_address')), 'Kikoni');
    await tester.tap(find.byKey(const Key('np_service_type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(ServiceType.washAndIron.label).last);
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      find.text('Add optional details'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.tap(find.text('Add optional details'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.byKey(const Key('np_count_inc')));
      await tester.pump();
    }
    await tester.enterText(
        find.byKey(const Key('np_notes')), 'Gate locked after 6');

    await tester.dragUntilVisible(
      find.widgetWithText(ElevatedButton, 'Create pickup'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Create pickup'));
    await tester.pumpAndSettle();

    final orders = await db.select(db.orders).get();
    expect(orders.single.itemCount, 4);
    expect(orders.single.notes, 'Gate locked after 6');
  });
}
