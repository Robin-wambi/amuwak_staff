import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:amuwak_staff/src/data/app_database.dart';
import 'package:amuwak_staff/src/orders/geo_services.dart';
import 'package:amuwak_staff/src/orders/new_pickup_result.dart';
import 'package:amuwak_staff/src/orders/new_pickup_screen.dart';
import 'package:amuwak_staff/src/orders/order.dart';
import 'package:amuwak_staff/src/orders/order_status.dart';
import 'package:amuwak_staff/src/orders/service_type.dart';
import 'package:amuwak_staff/src/sync/customers_repository.dart';
import 'package:amuwak_staff/src/sync/orders_repository.dart';

/// Online-only mode: NewPickupScreen takes [CustomersRepository] /
/// [OrdersRepository] (now Supabase-backed) via its constructor. These tests
/// mock those repos so they exercise the screen's UI behaviour without a
/// database — `getAll()` is stubbed for phone-match lookups, and writes are
/// verified by capturing the [Customer] / [LaundryOrder] passed to the repo
/// (replacing the old in-memory-Drift row inspection).
class _MockCustomersRepository extends Mock implements CustomersRepository {}

class _MockOrdersRepository extends Mock implements OrdersRepository {}

Customer _customer({
  required String id,
  required String name,
  required String phone,
  String? address,
}) =>
    Customer(
      id: id,
      name: name,
      phone: phone,
      address: address,
      notes: null,
      createdAt: DateTime(2026, 5, 20, 9),
      updatedAt: DateTime(2026, 5, 20, 9),
      deletedAt: null,
    );

void main() {
  setUpAll(() {
    registerFallbackValue(_customer(id: 'fb', name: 'fb', phone: '0'));
    registerFallbackValue(const LaundryOrder(
      orderId: 'fb',
      customerName: 'fb',
      serviceType: ServiceType.washAndIron,
      status: OrderStatus.pendingPickup,
      timeLabel: '',
      itemCount: 1,
      phone: '0',
      address: 'a',
      notes: '',
    ));
  });

  late _MockCustomersRepository customersRepo;
  late _MockOrdersRepository ordersRepo;

  setUp(() {
    customersRepo = _MockCustomersRepository();
    ordersRepo = _MockOrdersRepository();
    // Default: no existing customers (phone-match lookup finds nothing) and
    // writes succeed.
    when(() => customersRepo.getAll()).thenAnswer((_) async => <Customer>[]);
    when(() => customersRepo.upsertCustomer(any())).thenAnswer((_) async {});
    when(() => ordersRepo.upsertOrder(any(),
        actorStaffId: any(named: 'actorStaffId'))).thenAnswer((_) async {});
  });

  /// Captures the single [Customer] passed to [CustomersRepository.upsertCustomer].
  Customer capturedCustomer() =>
      verify(() => customersRepo.upsertCustomer(captureAny())).captured.single
          as Customer;

  /// Captures the single [LaundryOrder] passed to [OrdersRepository.upsertOrder].
  LaundryOrder capturedOrder() => verify(() => ordersRepo.upsertOrder(
        captureAny(),
        actorStaffId: any(named: 'actorStaffId'),
      )).captured.single as LaundryOrder;

  Future<_FormHandle> pumpFormAndOpen(
    WidgetTester tester, {
    GeolocateFn? geolocate,
    ReverseGeocodeFn? reverseGeocode,
  }) async {
    final handle = _FormHandle();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  handle.popped =
                      await Navigator.of(context).push<NewPickupResult>(
                    MaterialPageRoute(
                      builder: (_) => NewPickupScreen(
                        customersRepo: customersRepo,
                        ordersRepo: ordersRepo,
                        actorStaffId: 'staff-1',
                        clock: () => DateTime(2026, 5, 25, 10),
                        orderIdGenerator: () => 'uuid-order-1',
                        customerIdGenerator: () => 'uuid-cust-1',
                        geolocate: geolocate ?? () async => null,
                        reverseGeocode: reverseGeocode ?? (_) async => null,
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
    return handle;
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
    final handle = await pumpFormAndOpen(tester);

    await tester.enterText(find.byKey(const Key('np_name')), 'Jane Doe');
    await tester.enterText(find.byKey(const Key('np_phone')), '+256 700 111 222');
    await tester.enterText(find.byKey(const Key('np_address')), 'Kikoni, Kampala');
    await tester.tap(find.byKey(const Key('np_service_type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(ServiceType.washAndIron.label).last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Create pickup'));
    await tester.pumpAndSettle();

    expect(handle.popped, isNotNull);
    expect(handle.popped!.orderId, 'uuid-order-1');
    expect(handle.popped!.startPickupNow, isTrue);

    final customer = capturedCustomer();
    expect(customer.id, 'uuid-cust-1');
    expect(customer.name, 'Jane Doe');

    final order = capturedOrder();
    expect(order.orderId, 'uuid-order-1');
    expect(order.customerId, 'uuid-cust-1');
    expect(order.customerName, 'Jane Doe');
    expect(order.serviceType, ServiceType.washAndIron);
    expect(order.status, OrderStatus.pendingPickup);
    expect(order.scheduledFor, isNull);
    expect(order.orderCode, startsWith('AMW-'));
  });

  testWidgets('Cancel returns null and writes nothing', (tester) async {
    final handle = await pumpFormAndOpen(tester);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(handle.popped, isNull);
    verifyNever(() => customersRepo.upsertCustomer(any()));
    verifyNever(() => ordersRepo.upsertOrder(any(),
        actorStaffId: any(named: 'actorStaffId')));
  });

  testWidgets('Phone-on-blur with a matching customer shows the bottom sheet; '
      'tapping "Use this customer" pre-fills name + address', (tester) async {
    when(() => customersRepo.getAll()).thenAnswer((_) async => [
          _customer(
            id: 'existing-cust-1',
            name: 'Jane Existing',
            phone: '+256 700 111 222',
            address: 'Old address, Kampala',
          ),
        ]);
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
    when(() => customersRepo.getAll()).thenAnswer((_) async => [
          _customer(
            id: 'existing-cust-2',
            name: 'Bob Returning',
            phone: '+256 701 222 333',
            address: 'Wandegeya',
          ),
        ]);
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

    expect(capturedCustomer().id, 'existing-cust-2');
    expect(capturedOrder().customerId, 'existing-cust-2');
  });

  testWidgets(
      'Editing the phone field after accepting a customer match drops the '
      'cached customer id so submit creates a fresh customer row',
      (tester) async {
    when(() => customersRepo.getAll()).thenAnswer((_) async => [
          _customer(
            id: 'existing-cust-edited',
            name: 'Carol Original',
            phone: '+256 702 333 444',
            address: 'Original address',
          ),
        ]);
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

    // Cached match id was dropped → a fresh customer id is used, and the order
    // points at the new row (NOT the originally matched 'existing-cust-edited').
    final customer = capturedCustomer();
    expect(customer.id, 'uuid-cust-1');
    expect(customer.id, isNot('existing-cust-edited'));
    expect(capturedOrder().customerId, 'uuid-cust-1');
  });

  testWidgets('Use my location chip fills address from stubbed reverseGeocode',
      (tester) async {
    final handle = await pumpFormAndOpen(
      tester,
      geolocate: () async =>
          const GeoLocation(latitude: 0.3163, longitude: 32.5822),
      reverseGeocode: (_) async => 'Detected address, Kampala',
    );

    await tester.tap(find.widgetWithText(ActionChip, 'Use my location'));
    await tester.pumpAndSettle();

    expect(
      (tester.widget<TextFormField>(find.byKey(const Key('np_address')))).controller!.text,
      'Detected address, Kampala',
    );
    expect(handle.popped, isNull);
  });

  testWidgets(
      'Use my location chip shows a SnackBar when reverseGeocode returns '
      'null after a successful geolocate, and leaves the address blank',
      (tester) async {
    await pumpFormAndOpen(
      tester,
      geolocate: () async =>
          const GeoLocation(latitude: 0.3163, longitude: 32.5822),
      reverseGeocode: (_) async => null,
    );

    await tester.tap(find.widgetWithText(ActionChip, 'Use my location'));
    await tester.pumpAndSettle();

    expect(
      find.text('Could not determine address — please type it manually.'),
      findsOneWidget,
    );
    expect(
      (tester.widget<TextFormField>(find.byKey(const Key('np_address'))))
          .controller!
          .text,
      isEmpty,
    );
  });

  testWidgets('Schedule for later → Tomorrow morning sets scheduledFor to '
      '9 AM next day and pops with startPickupNow=false', (tester) async {
    final handle = await pumpFormAndOpen(tester);

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

    final tomorrowMorningChip = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, 'Tomorrow morning'));
    expect(tomorrowMorningChip.selected, isTrue);
    final inOneHourChip = tester
        .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'In 1 hour'));
    expect(inOneHourChip.selected, isFalse);
    expect(find.text('Scheduled for: Tomorrow, 9:00 AM'), findsOneWidget);

    await tester.dragUntilVisible(
      find.widgetWithText(ElevatedButton, 'Create pickup'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Create pickup'));
    await tester.pumpAndSettle();

    expect(handle.popped, isNotNull);
    expect(handle.popped!.startPickupNow, isFalse);
    expect(capturedOrder().scheduledFor, DateTime(2026, 5, 26, 9));
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

    final order = capturedOrder();
    expect(order.itemCount, 4);
    expect(order.notes, 'Gate locked after 6');
  });
}

/// Mutable holder so tests can read the value the form pops with AFTER the
/// pop has actually happened (i.e. after Cancel or Create pickup).
class _FormHandle {
  NewPickupResult? popped;
}
