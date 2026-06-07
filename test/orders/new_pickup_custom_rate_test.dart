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
    when(() => customersRepo.getAll()).thenAnswer((_) async => <Customer>[]);
    when(() => customersRepo.upsertCustomer(any())).thenAnswer((_) async {});
    when(() => ordersRepo.reserveOrderCode())
        .thenAnswer((_) async => 'AMW-2026-0001');
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

  Future<_FormHandle> pumpFormAndOpen(WidgetTester tester) async {
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
                        geolocate: () async => null,
                        reverseGeocode: (_) async => null,
                        defaultRatePerKgUgx: 5000,
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

  testWidgets('blank custom rate saves a null override', (tester) async {
    await pumpFormAndOpen(tester);

    await tester.enterText(find.byKey(const Key('np_name')), 'Jane Doe');
    await tester.enterText(
        find.byKey(const Key('np_phone')), '+256 700 111 222');
    await tester.enterText(
        find.byKey(const Key('np_address')), 'Kikoni, Kampala');
    await tester.tap(find.byKey(const Key('np_service_type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(ServiceType.washAndIron.label).last);
    await tester.pumpAndSettle();

    // Leave custom rate blank (do not expand optional details or leave field empty).
    await tester.tap(find.widgetWithText(ElevatedButton, 'Create pickup'));
    await tester.pumpAndSettle();

    final customer = capturedCustomer();
    expect(customer.customRatePerKgUgx, isNull,
        reason: 'blank custom rate field should save null override');
  });

  testWidgets('a positive custom rate is saved on the customer and order',
      (tester) async {
    await pumpFormAndOpen(tester);

    await tester.enterText(find.byKey(const Key('np_name')), 'Jane Doe');
    await tester.enterText(
        find.byKey(const Key('np_phone')), '+256 700 111 222');
    await tester.enterText(
        find.byKey(const Key('np_address')), 'Kikoni, Kampala');
    await tester.tap(find.byKey(const Key('np_service_type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(ServiceType.washAndIron.label).last);
    await tester.pumpAndSettle();

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
    await tester.enterText(find.byKey(const Key('np_custom_rate')), '4000');

    await tester.dragUntilVisible(
      find.widgetWithText(ElevatedButton, 'Create pickup'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Create pickup'));
    await tester.pumpAndSettle();

    final customer = capturedCustomer();
    expect(customer.customRatePerKgUgx, 4000.0,
        reason: 'custom rate should be saved on the customer');

    final order = capturedOrder();
    expect(order.ratePerKgSnapshotUgx, 4000.0,
        reason: 'order snapshot should use the typed custom rate');
  });
}

class _FormHandle {
  NewPickupResult? popped;
}
