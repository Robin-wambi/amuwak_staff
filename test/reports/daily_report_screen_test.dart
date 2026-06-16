import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_staff/src/orders/order.dart';
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
}
