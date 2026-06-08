import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:amuwak_staff/src/data/app_database.dart';
import 'package:amuwak_staff/src/orders/geo_services.dart';
import 'package:amuwak_staff/src/orders/new_pickup_screen.dart';
import 'package:amuwak_staff/src/orders/order.dart';
import 'package:amuwak_staff/src/orders/order_status.dart';
import 'package:amuwak_staff/src/orders/service_type.dart';
import 'package:amuwak_staff/src/sync/customers_repository.dart';
import 'package:amuwak_staff/src/sync/orders_repository.dart';

class _MockCustomersRepository extends Mock implements CustomersRepository {}

class _MockOrdersRepository extends Mock implements OrdersRepository {}

Customer _customer({
  required String id,
  required String name,
  required String phone,
  String? address,
  double? customRatePerKgUgx,
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
      customRatePerKgUgx: customRatePerKgUgx,
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
    when(() => customersRepo.getAll()).thenAnswer((_) async => <Customer>[]);
    when(() => customersRepo.upsertCustomer(any())).thenAnswer((_) async {});
    when(() => ordersRepo.reserveOrderCode())
        .thenAnswer((_) async => 'AMW-2026-0001');
    when(() => ordersRepo.upsertOrder(any(),
        actorStaffId: any(named: 'actorStaffId'))).thenAnswer((_) async {});
  });

  Widget buildScreen({double defaultRatePerKgUgx = 5000}) {
    return MaterialApp(
      home: NewPickupScreen(
        customersRepo: customersRepo,
        ordersRepo: ordersRepo,
        actorStaffId: 'staff-1',
        clock: () => DateTime(2026, 5, 25, 10),
        orderIdGenerator: () => 'uuid-order-1',
        customerIdGenerator: () => 'uuid-cust-1',
        geolocate: () async => null,
        reverseGeocode: (_) async => null,
        defaultRatePerKgUgx: defaultRatePerKgUgx,
      ),
    );
  }

  testWidgets('shows the default rate when no customer is matched',
      (tester) async {
    await tester.pumpWidget(buildScreen(defaultRatePerKgUgx: 5000));
    expect(find.text('Rate: USh 5,000/kg'), findsOneWidget);
  });

  testWidgets('shows a different default rate value correctly', (tester) async {
    await tester.pumpWidget(buildScreen(defaultRatePerKgUgx: 8000));
    expect(find.text('Rate: USh 8,000/kg'), findsOneWidget);
  });

  testWidgets(
      'switches to customer custom rate when a customer with override is matched',
      (tester) async {
    when(() => customersRepo.getAll()).thenAnswer((_) async => [
          _customer(
            id: 'cust-custom',
            name: 'VIP Client',
            phone: '+256 700 111 222',
            address: 'Kololo, Kampala',
            customRatePerKgUgx: 4000,
          ),
        ]);

    await tester.pumpWidget(buildScreen(defaultRatePerKgUgx: 5000));

    // Default rate is shown before match
    expect(find.text('Rate: USh 5,000/kg'), findsOneWidget);

    // Type a matching phone and blur to trigger the match sheet
    await tester.enterText(
        find.byKey(const Key('np_phone')), '+256 700 111 222');
    await tester.tap(find.byKey(const Key('np_name')));
    await tester.pumpAndSettle();

    // Match sheet appears — use the customer
    expect(find.text('Use this customer'), findsOneWidget);
    await tester.tap(find.text('Use this customer'));
    await tester.pumpAndSettle();

    // Rate should now show the customer's custom rate
    expect(find.text('Rate: USh 4,000/kg'), findsOneWidget);
    expect(find.text('Rate: USh 5,000/kg'), findsNothing);
  });

  testWidgets(
      'resets to default rate when phone is edited after a customer match',
      (tester) async {
    when(() => customersRepo.getAll()).thenAnswer((_) async => [
          _customer(
            id: 'cust-custom',
            name: 'VIP Client',
            phone: '+256 700 111 222',
            address: 'Kololo, Kampala',
            customRatePerKgUgx: 4000,
          ),
        ]);

    await tester.pumpWidget(buildScreen(defaultRatePerKgUgx: 5000));

    // Match a customer with a custom rate
    await tester.enterText(
        find.byKey(const Key('np_phone')), '+256 700 111 222');
    await tester.tap(find.byKey(const Key('np_name')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use this customer'));
    await tester.pumpAndSettle();
    expect(find.text('Rate: USh 4,000/kg'), findsOneWidget);

    // Edit the phone field — should reset rate to default
    await tester.enterText(
        find.byKey(const Key('np_phone')), '+256 702 999 999');
    await tester.pump();
    expect(find.text('Rate: USh 5,000/kg'), findsOneWidget);
    expect(find.text('Rate: USh 4,000/kg'), findsNothing);
  });

  testWidgets('rate label live-updates as a custom rate is typed',
      (tester) async {
    await tester.pumpWidget(buildScreen(defaultRatePerKgUgx: 5000));
    expect(find.text('Rate: USh 5,000/kg'), findsOneWidget);

    // Expand optional details and enter a custom rate.
    await tester.dragUntilVisible(
      find.text('Add optional details'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.tap(find.text('Add optional details'));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.byKey(const Key('np_custom_rate')),
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.enterText(find.byKey(const Key('np_custom_rate')), '4500');
    await tester.pump();

    // Scroll the label back into view and confirm it reflects the typed rate.
    await tester.dragUntilVisible(
      find.byKey(const Key('np_rate')),
      find.byType(ListView),
      const Offset(0, 200),
    );
    expect(find.text('Rate: USh 4,500/kg'), findsOneWidget);
    expect(find.text('Rate: USh 5,000/kg'), findsNothing);
  });

  testWidgets(
      'snapshot uses the default rate for an order with no customer override',
      (tester) async {
    await tester.pumpWidget(buildScreen(defaultRatePerKgUgx: 5000));

    await tester.enterText(find.byKey(const Key('np_name')), 'New Customer');
    await tester.enterText(
        find.byKey(const Key('np_phone')), '+256 700 111 222');
    await tester.enterText(find.byKey(const Key('np_address')), 'Kampala');
    await tester.tap(find.byKey(const Key('np_service_type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(ServiceType.washAndIron.label).last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Create pickup'));
    await tester.pumpAndSettle();

    final captured = verify(() => ordersRepo.upsertOrder(
          captureAny(),
          actorStaffId: any(named: 'actorStaffId'),
        )).captured.single as LaundryOrder;
    expect(captured.ratePerKgSnapshotUgx, 5000.0);
  });

  testWidgets('snapshot uses the customer custom rate when matched',
      (tester) async {
    when(() => customersRepo.getAll()).thenAnswer((_) async => [
          _customer(
            id: 'cust-custom-snap',
            name: 'VIP Client',
            phone: '+256 700 111 222',
            address: 'Kololo',
            customRatePerKgUgx: 4000,
          ),
        ]);

    await tester.pumpWidget(buildScreen(defaultRatePerKgUgx: 5000));

    await tester.enterText(
        find.byKey(const Key('np_phone')), '+256 700 111 222');
    await tester.tap(find.byKey(const Key('np_name')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use this customer'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('np_service_type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(ServiceType.washAndIron.label).last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Create pickup'));
    await tester.pumpAndSettle();

    final captured = verify(() => ordersRepo.upsertOrder(
          captureAny(),
          actorStaffId: any(named: 'actorStaffId'),
        )).captured.single as LaundryOrder;
    expect(captured.ratePerKgSnapshotUgx, 4000.0);
  });
}
