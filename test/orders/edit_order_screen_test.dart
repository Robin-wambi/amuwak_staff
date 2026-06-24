import 'package:amuwak_staff/src/orders/edit_order_screen.dart';
import 'package:amuwak_staff/src/orders/order.dart';
import 'package:amuwak_staff/src/orders/order_status.dart';
import 'package:amuwak_staff/src/orders/service_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The edit form changes only an order's descriptive fields and hands the
/// updated order back through the injected `save` callback (the dashboard wires
/// that to OrdersRepository.updateOrderDetails). Pricing and status are
/// deliberately out of scope here — they live on the details screen.
LaundryOrder _order() => LaundryOrder(
      orderId: 'o1',
      orderCode: 'AMW-1',
      customerName: 'Ada',
      serviceType: ServiceType.washAndIron,
      status: OrderStatus.inProgress,
      timeLabel: 'Today',
      itemCount: 3,
      phone: '0700',
      address: 'Kira',
      notes: 'gate code 4',
      // Pricing snapshot that must survive untouched through copyWith.
      ratePerKgSnapshotUgx: 5000,
      totalUgx: 19500,
    );

void main() {
  // A tall surface so the whole scrolling form lays out (the Notes field and
  // Save button sit below the default 800x600 viewport).
  Future<void> pumpTall(WidgetTester tester, Widget child) async {
    await tester.binding.setSurfaceSize(const Size(1200, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: child));
  }

  testWidgets('prefills the form from the order', (tester) async {
    await pumpTall(
      tester,
      EditOrderScreen(order: _order(), save: (_) async {}),
    );

    expect(find.text('Ada'), findsOneWidget);
    expect(find.text('0700'), findsOneWidget);
    expect(find.text('Kira'), findsOneWidget);
    expect(find.text('gate code 4'), findsOneWidget);
  });

  testWidgets('save passes an order with the edited fields, pricing intact',
      (tester) async {
    LaundryOrder? saved;
    await pumpTall(
      tester,
      EditOrderScreen(order: _order(), save: (o) async => saved = o),
    );

    await tester.enterText(find.byKey(const Key('edit_customer_name')), 'Bola');
    await tester.enterText(find.byKey(const Key('edit_phone')), '0800');
    await tester.tap(find.byKey(const Key('edit_save')));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.orderId, 'o1');
    expect(saved!.customerName, 'Bola');
    expect(saved!.phone, '0800');
    // Edits must not disturb the frozen pricing snapshot.
    expect(saved!.ratePerKgSnapshotUgx, 5000);
    expect(saved!.totalUgx, 19500);
    // Nor the status.
    expect(saved!.status, OrderStatus.inProgress);
  });

  testWidgets('a blank customer name is rejected before save', (tester) async {
    var saveCalled = false;
    await pumpTall(
      tester,
      EditOrderScreen(order: _order(), save: (_) async => saveCalled = true),
    );

    await tester.enterText(find.byKey(const Key('edit_customer_name')), '   ');
    await tester.tap(find.byKey(const Key('edit_save')));
    await tester.pumpAndSettle();

    expect(saveCalled, isFalse);
  });

  testWidgets('an empty item count is rejected before save', (tester) async {
    // The field is digitsOnly, so a literal "-1" can't be typed; the reachable
    // invalid path is an empty/non-numeric count, where int.tryParse returns
    // null and the same guard (itemCount == null || itemCount < 0) fires.
    var saveCalled = false;
    await pumpTall(
      tester,
      EditOrderScreen(order: _order(), save: (_) async => saveCalled = true),
    );

    await tester.enterText(find.byKey(const Key('edit_item_count')), '');
    await tester.tap(find.byKey(const Key('edit_save')));
    await tester.pumpAndSettle();

    expect(saveCalled, isFalse);
    expect(find.text('Enter a valid item count.'), findsOneWidget);
  });

  testWidgets('save carries an edited service type and notes', (tester) async {
    LaundryOrder? saved;
    await pumpTall(
      tester,
      EditOrderScreen(order: _order(), save: (o) async => saved = o),
    );

    await tester.tap(find.text(ServiceType.dryCleaning.label));
    await tester.enterText(
        find.byKey(const Key('edit_notes')), 'leave at the gate');
    await tester.tap(find.byKey(const Key('edit_save')));
    await tester.pumpAndSettle();

    expect(saved!.serviceType, ServiceType.dryCleaning);
    expect(saved!.notes, 'leave at the gate');
  });

  testWidgets('clearing the schedule sends an immediate (now) order',
      (tester) async {
    LaundryOrder? saved;
    final scheduled = _order().copyWith(scheduledFor: DateTime(2026, 7, 1, 9));
    await pumpTall(
      tester,
      EditOrderScreen(order: scheduled, save: (o) async => saved = o),
    );

    // The schedule reads as scheduled and offers a Clear affordance.
    expect(find.byKey(const Key('edit_clear_schedule')), findsOneWidget);
    expect(find.text('Immediate (pickup now)'), findsNothing);

    await tester.tap(find.byKey(const Key('edit_clear_schedule')));
    await tester.pumpAndSettle();
    expect(find.text('Immediate (pickup now)'), findsOneWidget);

    await tester.tap(find.byKey(const Key('edit_save')));
    await tester.pumpAndSettle();

    expect(saved!.scheduledFor, isNull);
    expect(saved!.timeLabel, 'Pickup: now');
  });

  testWidgets('picking a date + time sets a scheduledFor on save',
      (tester) async {
    LaundryOrder? saved;
    await pumpTall(
      tester,
      EditOrderScreen(order: _order(), save: (o) async => saved = o),
    );

    // Starts immediate.
    expect(find.text('Immediate (pickup now)'), findsOneWidget);

    await tester.tap(find.byKey(const Key('edit_pick_schedule')));
    await tester.pumpAndSettle();
    // Accept the date picker's initial date, then the time picker's initial
    // time (the dialogs' confirm button).
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('edit_save')));
    await tester.pumpAndSettle();

    expect(saved!.scheduledFor, isNotNull);
  });

  testWidgets('a successful save shows a confirmation SnackBar',
      (tester) async {
    await pumpTall(
      tester,
      EditOrderScreen(order: _order(), save: (_) async {}),
    );

    await tester.tap(find.byKey(const Key('edit_save')));
    await tester.pumpAndSettle();

    expect(find.text('Order updated.'), findsOneWidget);
  });

  testWidgets('a failing save surfaces a retry SnackBar', (tester) async {
    await pumpTall(
      tester,
      EditOrderScreen(
        order: _order(),
        save: (_) async => throw Exception('boom'),
      ),
    );

    await tester.tap(find.byKey(const Key('edit_save')));
    await tester.pumpAndSettle();

    expect(find.text('Could not save — please retry.'), findsOneWidget);
  });
}
