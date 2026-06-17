import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_staff/src/expenses/expense.dart';
import 'package:amuwak_staff/src/orders/order.dart';
import 'package:amuwak_staff/src/orders/order_filter.dart';
import 'package:amuwak_staff/src/orders/order_status.dart';
import 'package:amuwak_staff/src/orders/service_type.dart';
import 'package:amuwak_staff/src/reports/daily_report_screen.dart';
import 'package:amuwak_staff/src/shared/theme/app_card.dart';

// Default spend date is local Wed 2026-06-17 — matches [_fixedNow] so the
// daily window contains it. Pass [on] to place an expense on another day.
Expense _expense(ExpenseCategory category, int amountUgx, {DateTime? on}) =>
    Expense(
      id: '$category-$amountUgx-${on ?? ''}',
      category: category,
      amountUgx: amountUgx,
      note: '',
      spentAt: on ?? DateTime(2026, 6, 17, 8),
    );

// Fixed reference clock so the report's period window is deterministic in tests.
DateTime _fixedNow() => DateTime(2026, 6, 17, 12);

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
    final titles = <String?>[];
    var itemsTaps = 0;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DailyReportView(
          orders: [
            _order('A', OrderStatus.completed, 8000),
            _order('B', OrderStatus.inProgress, 5000),
          ],
          onOpenFiltered: (f, {title}) {
            filters.add(f);
            titles.add(title);
          },
          onOpenItems: () => itemsTaps++,
        ),
      ),
    ));

    await tester.tap(find.text('Orders'));
    // 'Completed' also appears in the Status breakdown card, so tap the metric
    // card via its unique icon instead of the ambiguous label.
    await tester.tap(find.byIcon(Icons.check_circle_outline_rounded));
    await tester.tap(find.text('Pending work'));
    await tester.tap(find.text('Items'));

    expect(filters, [
      OrderFilter.all,
      OrderFilter.completed,
      OrderFilter.pendingWork,
    ]);
    expect(titles, ['Orders', 'Completed', 'Pending work']);
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

  testWidgets(
      'Completed and Pending work cards show their OrderFilter counts',
      (tester) async {
    final orders = [
      _order('A', OrderStatus.completed, 1000),
      _order('B', OrderStatus.completed, 1000),
      _order('C', OrderStatus.inProgress, 1000),
      _order('D', OrderStatus.pendingPickup, 1000),
      _order('E', OrderStatus.readyForDelivery, 1000),
    ];
    // 2 completed, 3 not-completed (pending work).
    expect(OrderFilter.completed.count(orders), 2);
    expect(OrderFilter.pendingWork.count(orders), 3);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: DailyReportView(orders: orders)),
    ));

    // The number on each tappable card equals the count of the list it opens —
    // scope to the card via its unique icon to avoid matching the same digit
    // elsewhere on the report.
    Finder valueInCard(IconData icon, String value) => find.descendant(
          of: find.ancestor(
            of: find.byIcon(icon),
            matching: find.byType(AppCard),
          ),
          matching: find.text(value),
        );

    expect(valueInCard(Icons.check_circle_outline_rounded, '2'), findsOneWidget);
    expect(valueInCard(Icons.pending_actions_outlined, '3'), findsOneWidget);
  });

  testWidgets('shows per-category spend, total spent, and net profit',
      (tester) async {
    final orders = [
      _order('A', OrderStatus.completed, 10000),
      _order('B', OrderStatus.completed, 12000), // earned = 22,000
      _order('C', OrderStatus.inProgress, 5000), // expected = 5,000
    ];
    final expenses = [
      _expense(ExpenseCategory.detergent, 6000),
      _expense(ExpenseCategory.packaging, 3000), // total spent = 9,000
    ];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DailyReportView(
            orders: orders, expenses: expenses, now: _fixedNow),
      ),
    ));

    expect(find.text('Expenses'), findsOneWidget);
    expect(find.text('Detergent & cleaning'), findsOneWidget);
    expect(find.text('USh 6,000'), findsOneWidget);
    expect(find.text('Packaging'), findsOneWidget);
    expect(find.text('USh 3,000'), findsOneWidget);
    expect(find.text('Total spent'), findsOneWidget);
    expect(find.text('USh 9,000'), findsOneWidget);
    // Net = earned (22,000) − total spent (9,000).
    expect(find.text('Net'), findsOneWidget);
    expect(find.text('USh 13,000'), findsOneWidget);
  });

  testWidgets('net goes negative when spend exceeds earned revenue',
      (tester) async {
    final orders = [_order('A', OrderStatus.completed, 10000)]; // earned 10,000
    final expenses = [_expense(ExpenseCategory.fuel, 18000)]; // spent 18,000

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DailyReportView(
            orders: orders, expenses: expenses, now: _fixedNow),
      ),
    ));

    // Net = 10,000 − 18,000 = −8,000.
    expect(find.text('USh -8,000'), findsOneWidget);
  });

  testWidgets('shows the Expenses card with an Add action even when empty',
      (tester) async {
    var addTaps = 0;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DailyReportView(
          orders: const [],
          onAddExpense: () => addTaps++,
        ),
      ),
    ));

    // The card renders (so staff can record the first expense of the day) even
    // with no expenses yet.
    expect(find.text('Expenses'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.add));
    expect(addTaps, 1);
  });

  testWidgets('switching Daily→Weekly rescopes the period and its spend',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // now = Wed 2026-06-17. Its week starts Mon 2026-06-15. Two expenses fall
    // today and one on Monday; the Monday one is in the week but not the day.
    final expenses = [
      _expense(ExpenseCategory.detergent, 6000), // today (06-17)
      _expense(ExpenseCategory.packaging, 2000), // today (06-17)
      _expense(ExpenseCategory.fuel, 9000,
          on: DateTime(2026, 6, 15, 8)), // Monday — same week, not today
    ];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DailyReportView(
            orders: const [], expenses: expenses, now: _fixedNow),
      ),
    ));

    // Daily: header says Today; only today's spend (6,000 + 2,000) counts.
    expect(find.text("Today's report"), findsOneWidget);
    expect(find.text('USh 8,000'), findsOneWidget); // total spent (daily)

    await tester.tap(find.text('Weekly'));
    await tester.pumpAndSettle();

    // Weekly: header updates and Monday's 9,000 folds in (8,000 + 9,000).
    expect(find.text("This week's report"), findsOneWidget);
    expect(find.text('USh 17,000'), findsOneWidget); // total spent (weekly)
  });
}
