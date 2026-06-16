import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_staff/src/orders/order.dart';
import 'package:amuwak_staff/src/orders/order_status.dart';
import 'package:amuwak_staff/src/orders/service_type.dart';
import 'package:amuwak_staff/src/orders/widgets/order_card.dart';
import 'package:amuwak_staff/src/reports/items_breakdown_screen.dart';
import 'package:amuwak_staff/src/sync/repository_providers.dart';

LaundryOrder _order(String id, int itemCount) => LaundryOrder(
      orderId: id,
      orderCode: id,
      customerName: 'Cust $id',
      serviceType: ServiceType.washOnly,
      status: OrderStatus.inProgress,
      timeLabel: 't',
      itemCount: itemCount,
      phone: 'p',
      address: 'a',
      notes: '',
    );

Future<void> _pump(
  WidgetTester tester, {
  required List<LaundryOrder> orders,
  void Function(LaundryOrder)? onOrderTap,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ordersStreamProvider.overrideWith(
          (ref) => Stream<List<LaundryOrder>>.value(orders),
        ),
      ],
      child: MaterialApp(
        home: ItemsBreakdownScreen(onOrderTap: onOrderTap ?? (_) {}),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('app bar shows the Items title and the total-items header',
      (tester) async {
    await _pump(tester, orders: [_order('A', 3), _order('B', 2)]);

    expect(find.widgetWithText(AppBar, 'Items'), findsOneWidget);
    expect(find.text('Total items handled today: 5'), findsOneWidget);
  });

  testWidgets('lists orders that carry items, most-items-first', (tester) async {
    await _pump(tester, orders: [
      _order('low', 1),
      _order('high', 9),
      _order('mid', 4),
      _order('none', 0), // excluded: no items
    ]);

    expect(find.byType(OrderCard), findsNWidgets(3));

    // Ordered high -> mid -> low by vertical position.
    final highY = tester.getTopLeft(find.text('Cust high')).dy;
    final midY = tester.getTopLeft(find.text('Cust mid')).dy;
    final lowY = tester.getTopLeft(find.text('Cust low')).dy;
    expect(highY, lessThan(midY));
    expect(midY, lessThan(lowY));
    expect(find.text('Cust none'), findsNothing);
  });

  testWidgets('tapping a row invokes onOrderTap with that order', (tester) async {
    LaundryOrder? tapped;
    await _pump(
      tester,
      orders: [_order('A', 3)],
      onOrderTap: (o) => tapped = o,
    );

    await tester.tap(find.text('Cust A'));
    await tester.pumpAndSettle();

    expect(tapped?.orderId, 'A');
  });

  testWidgets('shows the empty state when no order has items', (tester) async {
    await _pump(tester, orders: [_order('A', 0)]);

    expect(find.text('No items yet'), findsOneWidget);
    expect(find.byType(OrderCard), findsNothing);
  });
}
