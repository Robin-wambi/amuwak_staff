# Tappable daily-report summary cards — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the four Daily-report summary cards (Orders, Items, Completed, Pending work) tappable, each opening its own page.

**Architecture:** Orders / Completed / Pending work reuse the existing `OrderFilterScreen` driven by two new `OrderFilter` values, so each card's count and the list it opens stay in lock-step. Items — which counts items, not orders — opens a new `ItemsBreakdownScreen`. `DailyReportView` gains optional navigation callbacks (mirroring `_HomeTab`); the dashboard's Report tab supplies them.

**Tech Stack:** Flutter, Riverpod, `flutter_test`. Tests run one file at a time (`flutter test <path>`) — running multiple paths hangs on this Windows host.

---

## File structure

- `lib/src/orders/order_filter.dart` — add `completed`, `pendingWork` enum values + their `label`/`newestFirst`/`matches` arms.
- `lib/src/reports/daily_report_screen.dart` — `DailyReportView` gains `onOpenFiltered`/`onOpenItems`; `_ReportMetricCard` gains `onTap`.
- `lib/src/reports/items_breakdown_screen.dart` — **new** read-only items breakdown page.
- `lib/src/dashboard/staff_dashboard_screen.dart` — Report tab passes the callbacks; new `_openItemsBreakdown()`.
- Tests: `test/orders/order_filter_test.dart`, `test/reports/daily_report_screen_test.dart`, `test/reports/items_breakdown_screen_test.dart` (new), `test/dashboard/staff_dashboard_screen_test.dart`.

---

## Task 1: Add `completed` and `pendingWork` to `OrderFilter`

**Files:**
- Modify: `lib/src/orders/order_filter.dart`
- Test: `test/orders/order_filter_test.dart`

- [ ] **Step 1: Write the failing tests**

Add these tests inside `void main() { ... }` in `test/orders/order_filter_test.dart` (after the existing `OrderFilter labels and sort direction` group):

```dart
  group('OrderFilter.completed (all-time)', () {
    final orders = [
      _order(OrderStatus.pendingPickup),
      _order(OrderStatus.inProgress),
      _order(OrderStatus.completed, deliveredAt: DateTime(2026, 6, 11, 9)),
      _order(OrderStatus.completed), // completed, no delivery proof
    ];

    test('matches every completed order regardless of delivery date', () {
      expect(OrderFilter.completed.apply(orders, now: now).length, 2);
    });

    test('count equals countByStatus(completed)', () {
      expect(
        OrderFilter.completed.count(orders, now: now),
        orders.countByStatus(OrderStatus.completed),
      );
    });

    test('label and newestFirst', () {
      expect(OrderFilter.completed.label, 'Completed');
      expect(OrderFilter.completed.newestFirst, isTrue);
    });
  });

  group('OrderFilter.pendingWork', () {
    final orders = [
      _order(OrderStatus.pendingPickup),
      _order(OrderStatus.inProgress),
      _order(OrderStatus.readyForDelivery),
      _order(OrderStatus.completed, deliveredAt: DateTime(2026, 6, 11, 9)),
    ];

    test('matches every not-completed order', () {
      expect(OrderFilter.pendingWork.apply(orders, now: now).length, 3);
    });

    test('count equals total minus completed', () {
      expect(
        OrderFilter.pendingWork.count(orders, now: now),
        orders.length - orders.countByStatus(OrderStatus.completed),
      );
    });

    test('label and newestFirst', () {
      expect(OrderFilter.pendingWork.label, 'Pending work');
      expect(OrderFilter.pendingWork.newestFirst, isFalse);
    });
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/orders/order_filter_test.dart`
Expected: FAIL — `completed`/`pendingWork` are not defined on `OrderFilter` (compile error).

- [ ] **Step 3: Add the enum values and switch arms**

In `lib/src/orders/order_filter.dart`, extend the enum declaration. Change:

```dart
  /// Orders *delivered today* (status completed + a delivery proof captured on
  /// the current calendar day). Distinct from an all-time completed count.
  completedToday;
```

to:

```dart
  /// Orders *delivered today* (status completed + a delivery proof captured on
  /// the current calendar day). Distinct from an all-time completed count.
  completedToday,

  /// Every completed order, all-time (status completed, no date constraint) —
  /// the daily report's "Completed" card.
  completed,

  /// Every order not yet completed — the daily report's "Pending work" card.
  pendingWork;
```

Add the `label` arms (inside the `switch (this)` for `label`, before the closing `}`):

```dart
        OrderFilter.completedToday => 'Completed today',
        OrderFilter.completed => 'Completed',
        OrderFilter.pendingWork => 'Pending work',
```

(The `completedToday` arm already exists — add the two new arms after it.)

Update `newestFirst` so completed work (both forms) reads most-recent-first. Change:

```dart
  bool get newestFirst => this == OrderFilter.completedToday;
```

to:

```dart
  bool get newestFirst =>
      this == OrderFilter.completedToday || this == OrderFilter.completed;
```

Add the `matches` arms (inside the `switch (this)` for `matches`, after the `completedToday` arm):

```dart
        OrderFilter.completed => o.status == OrderStatus.completed,
        OrderFilter.pendingWork => o.status != OrderStatus.completed,
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/orders/order_filter_test.dart`
Expected: PASS (the existing `count() equals apply().length for every filter` test now also covers the two new values).

- [ ] **Step 5: Commit**

```bash
git add lib/src/orders/order_filter.dart test/orders/order_filter_test.dart
git commit -m "feat(reports): add completed + pendingWork order filters" -- lib/src/orders/order_filter.dart test/orders/order_filter_test.dart
```

---

## Task 2: Make the report metric cards tappable

**Files:**
- Modify: `lib/src/reports/daily_report_screen.dart`
- Test: `test/reports/daily_report_screen_test.dart`

- [ ] **Step 1: Write the failing tests**

Add this import at the top of `test/reports/daily_report_screen_test.dart`:

```dart
import 'package:amuwak_staff/src/orders/order_filter.dart';
```

Add these tests inside `void main() { ... }`:

```dart
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
    await tester.tap(find.text('Completed'));
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

    // No metric card is wrapped in a tap handler, so tapping does nothing and
    // throws nothing.
    await tester.tap(find.text('Orders'), warnIfMissed: false);
    expect(tester.takeException(), isNull);
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/reports/daily_report_screen_test.dart`
Expected: FAIL — `DailyReportView` has no `onOpenFiltered`/`onOpenItems` parameters (compile error).

- [ ] **Step 3: Add the callbacks and wire the cards**

In `lib/src/reports/daily_report_screen.dart`, add the import near the other `../orders/` imports:

```dart
import '../orders/order_filter.dart';
```

Replace the `DailyReportView` constructor + fields:

```dart
class DailyReportView extends StatelessWidget {
  const DailyReportView({super.key, required this.orders});

  final List<LaundryOrder> orders;
```

with:

```dart
class DailyReportView extends StatelessWidget {
  const DailyReportView({
    super.key,
    required this.orders,
    this.onOpenFiltered,
    this.onOpenItems,
  });

  final List<LaundryOrder> orders;

  /// Opens the read-only list behind a tappable metric card. Null in the
  /// standalone/test render path, which leaves the cards inert.
  final void Function(OrderFilter filter)? onOpenFiltered;

  /// Opens the items breakdown page behind the "Items" card.
  final VoidCallback? onOpenItems;
```

In the same file, give `_ReportMetricCard` an `onTap`. Replace:

```dart
class _ReportMetricCard extends StatelessWidget {
  const _ReportMetricCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AppCard(
      child: Column(
```

with:

```dart
class _ReportMetricCard extends StatelessWidget {
  const _ReportMetricCard({
    required this.title,
    required this.value,
    required this.icon,
    this.onTap,
  });

  final String title;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AppCard(
      onTap: onTap,
      child: Column(
```

Now wire each card in `DailyReportView.build`. Add a local helper just before the `return SafeArea(` line:

```dart
    VoidCallback? openFilter(OrderFilter filter) =>
        onOpenFiltered == null ? null : () => onOpenFiltered!(filter);
```

Then update the four `_ReportMetricCard(...)` calls:

```dart
                child: _ReportMetricCard(
                  title: 'Orders',
                  value: '$totalOrders',
                  icon: Icons.assignment_outlined,
                  onTap: openFilter(OrderFilter.all),
                ),
```

```dart
                child: _ReportMetricCard(
                  title: 'Items',
                  value: '$totalItems',
                  icon: Icons.inventory_2_outlined,
                  onTap: onOpenItems,
                ),
```

```dart
                child: _ReportMetricCard(
                  title: OrderStatus.completed.label,
                  value: '$completed',
                  icon: Icons.check_circle_outline_rounded,
                  onTap: openFilter(OrderFilter.completed),
                ),
```

```dart
                child: _ReportMetricCard(
                  title: 'Pending work',
                  value: '$pendingWork',
                  icon: Icons.pending_actions_outlined,
                  onTap: openFilter(OrderFilter.pendingWork),
                ),
```

Note: the Completed card's title is `OrderStatus.completed.label` which is `'Completed'` — matching the `find.text('Completed')` in the test.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/reports/daily_report_screen_test.dart`
Expected: PASS (including the two pre-existing revenue tests, which construct `DailyReportView(orders: ...)` without callbacks).

- [ ] **Step 5: Commit**

```bash
git add lib/src/reports/daily_report_screen.dart test/reports/daily_report_screen_test.dart
git commit -m "feat(reports): make daily-report metric cards tappable" -- lib/src/reports/daily_report_screen.dart test/reports/daily_report_screen_test.dart
```

---

## Task 3: Add `ItemsBreakdownScreen`

**Files:**
- Create: `lib/src/reports/items_breakdown_screen.dart`
- Test: `test/reports/items_breakdown_screen_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/reports/items_breakdown_screen_test.dart`:

```dart
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

    // Ordered high → mid → low by vertical position.
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/reports/items_breakdown_screen_test.dart`
Expected: FAIL — `items_breakdown_screen.dart` does not exist (compile error).

- [ ] **Step 3: Create the screen**

Create `lib/src/reports/items_breakdown_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../orders/order.dart';
import '../orders/order_list_extensions.dart';
import '../orders/widgets/order_card.dart';
import '../shared/theme/app_spacing.dart';
import '../shared/widgets/empty_state.dart';
import '../sync/repository_providers.dart';

/// A read-only breakdown of how the day's items are distributed across orders.
///
/// Opened by tapping the "Items" card on the daily report. Items is a count,
/// not an order subset, so this page can't reuse [OrderFilterScreen]; instead it
/// lists the orders that carry items, most-items-first, under a running total.
///
/// Watches [ordersStreamProvider] so the list stays live, and delegates row
/// taps to [onOrderTap] (the dashboard's order-details opener, which carries the
/// session check + repository wiring).
class ItemsBreakdownScreen extends ConsumerWidget {
  const ItemsBreakdownScreen({super.key, required this.onOrderTap});

  final void Function(LaundryOrder order) onOrderTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(ordersStreamProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('Items')),
      body: ordersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const EmptyState(
          icon: Icons.error_outline_rounded,
          headline: "Couldn't load orders",
          subtitle: 'Please try again.',
        ),
        data: (orders) => _buildBody(context, orders),
      ),
    );
  }

  Widget _buildBody(BuildContext context, List<LaundryOrder> orders) {
    // Only orders that actually carry items, most-items-first. Ties break on
    // orderCode so the order of equal-count rows is stable.
    final withItems = orders.where((o) => o.itemCount > 0).toList()
      ..sort((a, b) {
        final byCount = b.itemCount.compareTo(a.itemCount);
        return byCount != 0 ? byCount : a.orderCode.compareTo(b.orderCode);
      });

    if (withItems.isEmpty) {
      return const EmptyState(
        icon: Icons.inventory_2_outlined,
        headline: 'No items yet',
        subtitle: 'No orders have items to show right now.',
      );
    }

    final totalItems = orders.totalItems;

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.xxl,
      ),
      // +1 for the total-items header row at index 0.
      itemCount: withItems.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Text(
              'Total items handled today: $totalItems',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          );
        }
        final order = withItems[index - 1];
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: OrderCard(order: order, onTap: () => onOrderTap(order)),
        );
      },
    );
  }
}
```

Note: verify `lib/src/shared/widgets/empty_state.dart` exports `EmptyState` with named params `icon`, `headline`, `subtitle` (it is used identically in `order_filter_screen.dart`). If the path or params differ, match that file.

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/reports/items_breakdown_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/reports/items_breakdown_screen.dart test/reports/items_breakdown_screen_test.dart
git commit -m "feat(reports): add items breakdown screen" -- lib/src/reports/items_breakdown_screen.dart test/reports/items_breakdown_screen_test.dart
```

---

## Task 4: Wire the Report tab to open the pages

**Files:**
- Modify: `lib/src/dashboard/staff_dashboard_screen.dart`
- Test: `test/dashboard/staff_dashboard_screen_test.dart`

- [ ] **Step 1: Write the failing tests**

Add this import near the other screen imports at the top of `test/dashboard/staff_dashboard_screen_test.dart`:

```dart
import 'package:amuwak_staff/src/reports/items_breakdown_screen.dart';
```

Add these tests inside `void main() { ... }` (e.g. after the existing tappable-summary-card tests):

```dart
  testWidgets(
    'Report tab: tapping the "Pending work" card opens the matching filter',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      const seeded = LaundryOrder(
        orderId: 'P1',
        orderCode: 'P1',
        customerName: 'Pending Cust',
        serviceType: ServiceType.washOnly,
        status: OrderStatus.inProgress,
        timeLabel: 't',
        itemCount: 2,
        phone: 'p',
        address: 'a',
        notes: '',
      );

      await pumpDashboardWithDb(tester, extraOverrides: [
        ordersStreamProvider.overrideWith(
          (ref) => Stream<List<LaundryOrder>>.value(const [seeded]),
        ),
      ]);

      await tester.tap(find.text('Report').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pending work'));
      await tester.pumpAndSettle();

      expect(find.byType(OrderFilterScreen), findsOneWidget);
      expect(find.widgetWithText(AppBar, 'Pending work'), findsOneWidget);
      expect(find.text('Pending Cust'), findsOneWidget);
    },
  );

  testWidgets(
    'Report tab: tapping the "Items" card opens ItemsBreakdownScreen',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      const seeded = LaundryOrder(
        orderId: 'I1',
        orderCode: 'I1',
        customerName: 'Items Cust',
        serviceType: ServiceType.washOnly,
        status: OrderStatus.inProgress,
        timeLabel: 't',
        itemCount: 4,
        phone: 'p',
        address: 'a',
        notes: '',
      );

      await pumpDashboardWithDb(tester, extraOverrides: [
        ordersStreamProvider.overrideWith(
          (ref) => Stream<List<LaundryOrder>>.value(const [seeded]),
        ),
      ]);

      await tester.tap(find.text('Report').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Items'));
      await tester.pumpAndSettle();

      expect(find.byType(ItemsBreakdownScreen), findsOneWidget);
      expect(find.text('Total items handled today: 4'), findsOneWidget);
    },
  );
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/dashboard/staff_dashboard_screen_test.dart`
Expected: FAIL — the Report-tab `DailyReportView` passes no callbacks, so the cards are inert: tapping `'Pending work'` / `'Items'` pushes nothing, and `ItemsBreakdownScreen` is an unresolved import.

- [ ] **Step 3: Wire the dashboard**

In `lib/src/dashboard/staff_dashboard_screen.dart`, add the import next to the existing `import '../reports/daily_report_screen.dart';`:

```dart
import '../reports/items_breakdown_screen.dart';
```

Add a navigation helper next to `_openFilteredOrders` (after its closing `}`):

```dart
  /// Opens the items breakdown behind the daily report's "Items" card. Reuses
  /// [_openOrderDetails] for row taps so the session check + repository wiring
  /// live in one place.
  void _openItemsBreakdown() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ItemsBreakdownScreen(onOrderTap: _openOrderDetails),
      ),
    );
  }
```

Update the Report tab branch (`case 2`) to pass the callbacks. Replace:

```dart
          2 => ordersAsync.when(
              data: (orders) => DailyReportView(orders: orders),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => _ErrorRetry(
                onRetry: () => ref.invalidate(ordersStreamProvider),
              ),
            ),
```

with:

```dart
          2 => ordersAsync.when(
              data: (orders) => DailyReportView(
                orders: orders,
                onOpenFiltered: _openFilteredOrders,
                onOpenItems: _openItemsBreakdown,
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => _ErrorRetry(
                onRetry: () => ref.invalidate(ordersStreamProvider),
              ),
            ),
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/dashboard/staff_dashboard_screen_test.dart`
Expected: PASS (existing dashboard tests unaffected).

- [ ] **Step 5: Commit**

```bash
git add lib/src/dashboard/staff_dashboard_screen.dart test/dashboard/staff_dashboard_screen_test.dart
git commit -m "feat(reports): open report cards into filtered + items pages" -- lib/src/dashboard/staff_dashboard_screen.dart test/dashboard/staff_dashboard_screen_test.dart
```

---

## Final verification

- [ ] Run each touched test file once more, one at a time:
  - `flutter test test/orders/order_filter_test.dart`
  - `flutter test test/reports/daily_report_screen_test.dart`
  - `flutter test test/reports/items_breakdown_screen_test.dart`
  - `flutter test test/dashboard/staff_dashboard_screen_test.dart`
- [ ] `flutter analyze` is clean for the touched files (no new warnings).

---

## Self-review notes

- **Spec coverage:** Task 1 (new filters) → Task 2 (tappable cards + Items hook) → Task 3 (`ItemsBreakdownScreen`, most-items-first, tappable rows, total header, empty state) → Task 4 (dashboard wiring). All spec components are covered.
- **Type consistency:** `onOpenFiltered`/`onOpenItems` names, `ItemsBreakdownScreen({onOrderTap})`, and the new `OrderFilter.completed`/`OrderFilter.pendingWork` values are used identically across tasks and tests.
- **Out of scope (unchanged):** card counts/values, report data scope, offline paths.
