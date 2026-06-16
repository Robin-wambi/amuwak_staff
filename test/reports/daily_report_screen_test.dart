import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_staff/src/orders/order.dart';
import 'package:amuwak_staff/src/orders/order_filter.dart';
import 'package:amuwak_staff/src/orders/order_status.dart';
import 'package:amuwak_staff/src/orders/service_type.dart';
import 'package:amuwak_staff/src/reports/daily_report_screen.dart';

LaundryOrder _order(String id, OrderStatus status, int totalUgx) => LaundryOrder(
      orderId: id,
      orderCode: id,
      customerName: 'X',
      serviceType: ServiceType.washOnly,
      status: status,
      timeLabel: 't',
      itemCount: 1,
      phone: '0700123456',
      address: 'addr',
      notes: '',
      totalUgx: totalUgx,
    );

void main() {
  testWidgets('renders earned, expected, and total booked revenue',
      (tester) async {
    final orders = [
      _order('A', OrderStatus.completed, 8000),
      _order('B', OrderStatus.completed, 12000),
      _order('C', OrderStatus.inProgress, 5000),
      _order('D', OrderStatus.pendingPickup, 3000),
    ];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: DailyReportView(orders: orders)),
    ));

    // Section heading present.
    expect(find.text('Revenue'), findsOneWidget);
    expect(find.text('Earned'), findsOneWidget);
    expect(find.text('Expected'), findsOneWidget);
    expect(find.text('Total booked'), findsOneWidget);

    // Earned = completed totals (8000 + 12000).
    expect(find.text('USh 20,000'), findsOneWidget);
    // Expected = non-completed totals (5000 + 3000).
    expect(find.text('USh 8,000'), findsOneWidget);
    // Total booked = earned + expected.
    expect(find.text('USh 28,000'), findsOneWidget);
  });

  testWidgets('shows zero revenue for an empty order list', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: DailyReportView(orders: [])),
    ));

    expect(find.text('Revenue'), findsOneWidget);
    // Earned, Expected, and Total booked all render USh 0.
    expect(find.text('USh 0'), findsNWidgets(3));
  });

  testWidgets('each card invokes the right navigation callback', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final filters = <OrderFilter>[];
    var itemsTaps = 0;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DailyReportView(
          orders: [
            _order('A', OrderStatus.completed, 8000),
            _order('B', OrderStatus.inProgress, 5000),
          ],
          onOpenFiltered: filters.add,
          onOpenItems: () => itemsTaps++,
        ),
      ),
    ));

    await tester.tap(find.text('Orders'));
    // "Completed" also appears in the status-breakdown card, so scope the tap
    // to the metric card identified by its check icon.
    await tester.tap(find.descendant(
      of: find.ancestor(
        of: find.byIcon(Icons.check_circle_outline_rounded),
        matching: find.byType(GestureDetector),
      ),
      matching: find.text('Completed'),
    ));
    await tester.tap(find.text('Pending work'));
    await tester.tap(find.text('Items'));

    expect(filters, [
      OrderFilter.all,
      OrderFilter.completed,
      OrderFilter.pendingWork,
    ]);
    expect(itemsTaps, 1);
  });

  testWidgets('cards are inert when no callbacks are provided', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DailyReportView(orders: [
          _order('A', OrderStatus.completed, 8000),
        ]),
      ),
    ));

    await tester.tap(find.text('Orders'), warnIfMissed: false);
    expect(tester.takeException(), isNull);
  });
}
