# Notifications Summary Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the placeholder `NotificationsScreen` with a live summary of new pickup orders and recently-delivered orders (rolling 48h), derived entirely from the existing orders stream, plus a new-pickup count badge on the dashboard bell.

**Architecture:** A pure `NotificationSummary.fromOrders(orders, now:)` helper filters the in-memory `List<LaundryOrder>` from `ordersStreamProvider` into new pickups (status `pendingPickup`) and delivered orders (a `delivery` proof event captured within 48h). `NotificationsScreen` becomes a Riverpod `ConsumerWidget` that watches that provider, renders count chips + a merged "Recent" feed, and opens Order Details via an injected `onOrderTap` callback (same pattern as `OrderSearchScreen`). No new repository, table, or backend.

**Tech Stack:** Flutter, Riverpod (`flutter_riverpod`), Material 3 `Badge`, existing theme primitives (`AppCard`, `AppSpacing`, `AppColors`, `AppRadii`), `flutter_test`.

---

## File Structure

- **Create** `lib/src/notifications/notification_summary.dart` — pure model: `NotificationKind` enum, `NotificationItem`, `NotificationSummary` + `fromOrders` factory, `kDeliveredWindow` constant. No Flutter imports.
- **Create** `lib/src/notifications/relative_time.dart` — pure `relativeTimeLabel(DateTime, {required DateTime now})` helper.
- **Rewrite** `lib/src/notifications/notifications_screen.dart` — `ConsumerWidget`; watches `ordersStreamProvider`; renders chips + feed + empty state; private `_CountChip` and `_NotificationRow` widgets.
- **Modify** `lib/src/dashboard/staff_dashboard_screen.dart` — pass `onOrderTap: _openOrderDetails` into `NotificationsScreen`; wrap the AppBar bell icon in a `Badge` driven by the new-pickup count.
- **Create** `test/notifications/notification_summary_test.dart` — pure unit tests.
- **Create** `test/notifications/relative_time_test.dart` — pure unit tests.
- **Rewrite** `test/notifications/notifications_screen_test.dart` — widget tests (empty + populated + tap + loading/error).

### Locked-in ordering rule (resolves the spec's open question)
The "Recent" feed is **new pickups first** (most imminent — `scheduledFor` ascending, nulls last, then `orderCode` for stability), **then delivered** (most recent — `capturedAt` descending). Pickups are the rider's to-do; delivered is the done.

### Display fields per row
- **New pickup row:** bag icon, title `New pickup · {orderCode}`, subtitle `{customerName} · {timeLabel}`.
- **Delivered row:** check icon, title `Delivered · {orderCode}`, subtitle `{customerName} · {relativeTimeLabel(capturedAt, now)}`.

`LaundryOrder` already exposes: `orderCode`, `customerName`, `status` (`OrderStatus`), `timeLabel` (String), `scheduledFor` (`DateTime?`), and `deliveryProof` (`ProofEvent?` with `capturedAt`).

---

## Task 1: `NotificationSummary` pure model

**Files:**
- Create: `lib/src/notifications/notification_summary.dart`
- Test: `test/notifications/notification_summary_test.dart`

- [ ] **Step 1: Write the failing tests**

Create `test/notifications/notification_summary_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_staff/src/notifications/notification_summary.dart';
import 'package:amuwak_staff/src/orders/order.dart';
import 'package:amuwak_staff/src/orders/order_status.dart';
import 'package:amuwak_staff/src/orders/proof_event.dart';
import 'package:amuwak_staff/src/orders/service_type.dart';

LaundryOrder _order({
  required String code,
  required OrderStatus status,
  DateTime? scheduledFor,
  DateTime? deliveredAt,
}) {
  return LaundryOrder(
    orderId: 'id-$code',
    orderCode: code,
    customerName: 'Cust $code',
    serviceType: ServiceType.washAndIron,
    status: status,
    timeLabel: 'Today',
    itemCount: 1,
    phone: '0700000000',
    address: 'Somewhere',
    notes: '',
    scheduledFor: scheduledFor,
    proofEvents: [
      if (deliveredAt != null)
        ProofEvent(
          id: 'pe-$code',
          type: ProofEventType.delivery,
          capturedAt: deliveredAt,
          count: 1,
          photoPaths: const [],
        ),
    ],
  );
}

void main() {
  final now = DateTime.utc(2026, 6, 5, 12, 0);

  test('new pickups are orders with pendingPickup status', () {
    final summary = NotificationSummary.fromOrders([
      _order(code: 'P1', status: OrderStatus.pendingPickup),
      _order(code: 'I1', status: OrderStatus.inProgress),
    ], now: now);

    expect(summary.newPickups.map((o) => o.orderCode), ['P1']);
  });

  test('delivered includes orders with a delivery proof inside the 48h window', () {
    final summary = NotificationSummary.fromOrders([
      _order(
        code: 'D1',
        status: OrderStatus.completed,
        deliveredAt: now.subtract(const Duration(hours: 1)),
      ),
    ], now: now);

    expect(summary.delivered.map((o) => o.orderCode), ['D1']);
  });

  test('delivered excludes a delivery proof older than the 48h window', () {
    final summary = NotificationSummary.fromOrders([
      _order(
        code: 'OLD',
        status: OrderStatus.completed,
        deliveredAt: now.subtract(const Duration(hours: 49)),
      ),
    ], now: now);

    expect(summary.delivered, isEmpty);
  });

  test('delivered is sorted most-recent first', () {
    final summary = NotificationSummary.fromOrders([
      _order(
        code: 'OLDER',
        status: OrderStatus.completed,
        deliveredAt: now.subtract(const Duration(hours: 10)),
      ),
      _order(
        code: 'NEWER',
        status: OrderStatus.completed,
        deliveredAt: now.subtract(const Duration(hours: 2)),
      ),
    ], now: now);

    expect(summary.delivered.map((o) => o.orderCode), ['NEWER', 'OLDER']);
  });

  test('new pickups are sorted by scheduledFor ascending, nulls last', () {
    final summary = NotificationSummary.fromOrders([
      _order(code: 'LATER', status: OrderStatus.pendingPickup,
          scheduledFor: now.add(const Duration(hours: 3))),
      _order(code: 'NONE', status: OrderStatus.pendingPickup),
      _order(code: 'SOON', status: OrderStatus.pendingPickup,
          scheduledFor: now.add(const Duration(hours: 1))),
    ], now: now);

    expect(summary.newPickups.map((o) => o.orderCode), ['SOON', 'LATER', 'NONE']);
  });

  test('recent feed is pickups first then delivered', () {
    final summary = NotificationSummary.fromOrders([
      _order(
        code: 'D1',
        status: OrderStatus.completed,
        deliveredAt: now.subtract(const Duration(hours: 1)),
      ),
      _order(code: 'P1', status: OrderStatus.pendingPickup,
          scheduledFor: now.add(const Duration(hours: 1))),
    ], now: now);

    expect(
      summary.recent.map((i) => '${i.kind.name}:${i.order.orderCode}'),
      ['newPickup:P1', 'delivered:D1'],
    );
  });

  test('isEmpty is true when there are no pickups and nothing delivered', () {
    final summary = NotificationSummary.fromOrders([
      _order(code: 'I1', status: OrderStatus.inProgress),
    ], now: now);

    expect(summary.isEmpty, isTrue);
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/notifications/notification_summary_test.dart`
Expected: FAIL — `notification_summary.dart` does not exist / `NotificationSummary` undefined.

- [ ] **Step 3: Write the implementation**

Create `lib/src/notifications/notification_summary.dart`:

```dart
import '../orders/order.dart';
import '../orders/order_status.dart';
import '../orders/proof_event.dart';

/// How far back a delivered order stays in the summary feed.
const Duration kDeliveredWindow = Duration(hours: 48);

enum NotificationKind { newPickup, delivered }

/// One row in the Recent feed: an order plus why it is here.
class NotificationItem {
  const NotificationItem({required this.order, required this.kind});

  final LaundryOrder order;
  final NotificationKind kind;
}

/// Derived, read-only summary of the orders a rider cares about at a glance.
///
/// Pure: all filtering/sorting happens here from the in-memory orders list,
/// with [now] injected so it is deterministic under test. No I/O, no Flutter.
class NotificationSummary {
  const NotificationSummary({
    required this.newPickups,
    required this.delivered,
  });

  final List<LaundryOrder> newPickups;
  final List<LaundryOrder> delivered;

  factory NotificationSummary.fromOrders(
    List<LaundryOrder> orders, {
    required DateTime now,
  }) {
    final pickups = orders
        .where((o) => o.status == OrderStatus.pendingPickup)
        .toList()
      ..sort(_byScheduledForAscNullsLast);

    final cutoff = now.subtract(kDeliveredWindow);
    final delivered = orders.where((o) {
      final proof = o.deliveryProof;
      return proof != null && proof.capturedAt.isAfter(cutoff);
    }).toList()
      ..sort((a, b) =>
          b.deliveryProof!.capturedAt.compareTo(a.deliveryProof!.capturedAt));

    return NotificationSummary(newPickups: pickups, delivered: delivered);
  }

  /// Merged feed: pickups (imminent first) then delivered (most recent first).
  List<NotificationItem> get recent => [
        for (final o in newPickups)
          NotificationItem(order: o, kind: NotificationKind.newPickup),
        for (final o in delivered)
          NotificationItem(order: o, kind: NotificationKind.delivered),
      ];

  bool get isEmpty => newPickups.isEmpty && delivered.isEmpty;

  static int _byScheduledForAscNullsLast(LaundryOrder a, LaundryOrder b) {
    final sa = a.scheduledFor;
    final sb = b.scheduledFor;
    if (sa == null && sb == null) return a.orderCode.compareTo(b.orderCode);
    if (sa == null) return 1; // nulls last
    if (sb == null) return -1;
    final cmp = sa.compareTo(sb);
    return cmp != 0 ? cmp : a.orderCode.compareTo(b.orderCode);
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/notifications/notification_summary_test.dart`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/src/notifications/notification_summary.dart test/notifications/notification_summary_test.dart
git commit -m "feat(notifications): derive new-pickup + delivered summary from orders"
```

---

## Task 2: `relativeTimeLabel` helper

**Files:**
- Create: `lib/src/notifications/relative_time.dart`
- Test: `test/notifications/relative_time_test.dart`

- [ ] **Step 1: Write the failing tests**

Create `test/notifications/relative_time_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_staff/src/notifications/relative_time.dart';

void main() {
  final now = DateTime.utc(2026, 6, 5, 12, 0);

  String label(Duration ago) =>
      relativeTimeLabel(now.subtract(ago), now: now);

  test('under a minute reads "just now"', () {
    expect(label(const Duration(seconds: 30)), 'just now');
  });

  test('minutes', () {
    expect(label(const Duration(minutes: 1)), '1 min ago');
    expect(label(const Duration(minutes: 45)), '45 min ago');
  });

  test('hours', () {
    expect(label(const Duration(hours: 1)), '1 hr ago');
    expect(label(const Duration(hours: 5)), '5 hr ago');
  });

  test('days', () {
    expect(label(const Duration(hours: 24)), '1 day ago');
    expect(label(const Duration(hours: 47)), '1 day ago');
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/notifications/relative_time_test.dart`
Expected: FAIL — `relative_time.dart` does not exist.

- [ ] **Step 3: Write the implementation**

Create `lib/src/notifications/relative_time.dart`:

```dart
/// Short, scannable relative-time label for a past instant ("4 min ago").
///
/// Pure: [now] is injected so callers (and tests) stay deterministic.
String relativeTimeLabel(DateTime time, {required DateTime now}) {
  final diff = now.difference(time);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} hr ago';
  final days = diff.inDays;
  return '$days day${days == 1 ? '' : 's'} ago';
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/notifications/relative_time_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/src/notifications/relative_time.dart test/notifications/relative_time_test.dart
git commit -m "feat(notifications): add relative-time label helper"
```

---

## Task 3: Rewrite `NotificationsScreen` as a live summary

**Files:**
- Rewrite: `lib/src/notifications/notifications_screen.dart`
- Rewrite: `test/notifications/notifications_screen_test.dart`

- [ ] **Step 1: Write the failing widget tests**

Replace the contents of `test/notifications/notifications_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_staff/src/notifications/notifications_screen.dart';
import 'package:amuwak_staff/src/orders/order.dart';
import 'package:amuwak_staff/src/orders/order_status.dart';
import 'package:amuwak_staff/src/orders/proof_event.dart';
import 'package:amuwak_staff/src/orders/service_type.dart';
import 'package:amuwak_staff/src/sync/repository_providers.dart';

final _now = DateTime.utc(2026, 6, 5, 12, 0);

LaundryOrder _order({
  required String code,
  required OrderStatus status,
  DateTime? deliveredAt,
}) {
  return LaundryOrder(
    orderId: 'id-$code',
    orderCode: code,
    customerName: 'Cust $code',
    serviceType: ServiceType.washAndIron,
    status: status,
    timeLabel: 'Today',
    itemCount: 1,
    phone: '0700000000',
    address: 'Somewhere',
    notes: '',
    proofEvents: [
      if (deliveredAt != null)
        ProofEvent(
          id: 'pe-$code',
          type: ProofEventType.delivery,
          capturedAt: deliveredAt,
          count: 1,
          photoPaths: const [],
        ),
    ],
  );
}

Widget _harness(
  List<LaundryOrder> orders, {
  void Function(LaundryOrder)? onOrderTap,
}) {
  return ProviderScope(
    overrides: [
      ordersStreamProvider.overrideWith((ref) => Stream.value(orders)),
    ],
    child: MaterialApp(
      home: NotificationsScreen(
        onOrderTap: onOrderTap,
        clock: () => _now,
      ),
    ),
  );
}

void main() {
  testWidgets('shows the empty state when nothing to summarize', (tester) async {
    await tester.pumpWidget(_harness([
      _order(code: 'I1', status: OrderStatus.inProgress),
    ]));
    await tester.pump();

    expect(find.text('No notifications yet.'), findsOneWidget);
    expect(find.byIcon(Icons.notifications_off_outlined), findsOneWidget);
  });

  testWidgets('renders count chips and feed rows', (tester) async {
    await tester.pumpWidget(_harness([
      _order(code: 'P1', status: OrderStatus.pendingPickup),
      _order(
        code: 'D1',
        status: OrderStatus.completed,
        deliveredAt: _now.subtract(const Duration(minutes: 5)),
      ),
    ]));
    await tester.pump();

    expect(find.text('New pickup · P1'), findsOneWidget);
    expect(find.text('Delivered · D1'), findsOneWidget);
    expect(find.textContaining('5 min ago'), findsOneWidget);
  });

  testWidgets('tapping a row invokes onOrderTap with that order', (tester) async {
    LaundryOrder? tapped;
    await tester.pumpWidget(_harness(
      [_order(code: 'P1', status: OrderStatus.pendingPickup)],
      onOrderTap: (o) => tapped = o,
    ));
    await tester.pump();

    await tester.tap(find.text('New pickup · P1'));
    await tester.pump();

    expect(tapped?.orderCode, 'P1');
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/notifications/notifications_screen_test.dart`
Expected: FAIL — `NotificationsScreen` has no `onOrderTap`/`clock` params.

- [ ] **Step 3: Write the implementation**

Replace the contents of `lib/src/notifications/notifications_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../orders/order.dart';
import '../shared/theme/app_card.dart';
import '../shared/theme/app_colors.dart';
import '../shared/theme/app_radii.dart';
import '../shared/theme/app_spacing.dart';
import '../shared/widgets/empty_state.dart';
import '../sync/repository_providers.dart';
import 'notification_summary.dart';
import 'relative_time.dart';

/// Live summary of new pickup orders and recently-delivered orders (48h),
/// derived from the same orders stream the dashboard watches.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({
    super.key,
    this.onOrderTap,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Opens Order Details for a tapped row. The dashboard passes its existing
  /// `_openOrderDetails`; null in isolation (e.g. tests that only assert UI).
  final void Function(LaundryOrder order)? onOrderTap;

  final DateTime Function() _clock;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(ordersStreamProvider);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        elevation: 0,
        title: const Text('Notifications'),
      ),
      body: ordersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _ErrorRetry(
          onRetry: () => ref.invalidate(ordersStreamProvider),
        ),
        data: (orders) {
          final summary =
              NotificationSummary.fromOrders(orders, now: _clock());
          if (summary.isEmpty) {
            return const EmptyState(
              icon: Icons.notifications_off_outlined,
              headline: 'No notifications yet.',
              subtitle:
                  "We'll let you know when something needs your attention.",
            );
          }
          return _SummaryBody(
            summary: summary,
            now: _clock(),
            onOrderTap: onOrderTap,
          );
        },
      ),
    );
  }
}

class _SummaryBody extends StatelessWidget {
  const _SummaryBody({
    required this.summary,
    required this.now,
    required this.onOrderTap,
  });

  final NotificationSummary summary;
  final DateTime now;
  final void Function(LaundryOrder order)? onOrderTap;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Row(
          children: [
            Expanded(
              child: _CountChip(
                count: summary.newPickups.length,
                label: 'New pickups',
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _CountChip(
                count: summary.delivered.length,
                label: 'Delivered · 48h',
                color: const Color(0xFF2E7D32),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('Recent', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: AppSpacing.sm),
        for (final item in summary.recent)
          _NotificationRow(item: item, now: now, onOrderTap: onOrderTap),
      ],
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({
    required this.count,
    required this.label,
    required this.color,
  });

  final int count;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadii.field),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$count',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _NotificationRow extends StatelessWidget {
  const _NotificationRow({
    required this.item,
    required this.now,
    required this.onOrderTap,
  });

  final NotificationItem item;
  final DateTime now;
  final void Function(LaundryOrder order)? onOrderTap;

  @override
  Widget build(BuildContext context) {
    final isPickup = item.kind == NotificationKind.newPickup;
    final order = item.order;
    final colorScheme = Theme.of(context).colorScheme;
    final accent = isPickup ? colorScheme.primary : const Color(0xFF2E7D32);

    final title = isPickup
        ? 'New pickup · ${order.orderCode}'
        : 'Delivered · ${order.orderCode}';
    final subtitle = isPickup
        ? '${order.customerName} · ${order.timeLabel}'
        : '${order.customerName} · '
            '${relativeTimeLabel(order.deliveryProof!.capturedAt, now: now)}';

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        onTap: onOrderTap == null ? null : () => onOrderTap!(order),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadii.field - 2),
              ),
              child: Icon(
                isPickup
                    ? Icons.shopping_bag_outlined
                    : Icons.check_circle_outline,
                color: accent,
                size: 20,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: AppSpacing.xs / 2),
                  Text(subtitle,
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.secondaryText),
          ],
        ),
      ),
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text("Couldn't load notifications."),
          const SizedBox(height: AppSpacing.md),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
```

> **Note on `AppCard.onTap`:** verified `VoidCallback?` (nullable). A null `onTap` renders an inert, non-interactive card (no `InkWell`), so `onTap: onOrderTap == null ? null : () => onOrderTap!(order)` is correct as written.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/notifications/notifications_screen_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Run analyzer on the new files**

Run: `flutter analyze lib/src/notifications`
Expected: No issues.

- [ ] **Step 6: Commit**

```bash
git add lib/src/notifications/notifications_screen.dart test/notifications/notifications_screen_test.dart
git commit -m "feat(notifications): live summary screen with count chips + recent feed"
```

---

## Task 4: Wire the dashboard (callback + bell badge)

**Files:**
- Modify: `lib/src/dashboard/staff_dashboard_screen.dart` (NotificationsScreen push ~line 324; AppBar bell ~lines 320-327)

- [ ] **Step 1: Pass `onOrderTap` into `NotificationsScreen`**

In `lib/src/dashboard/staff_dashboard_screen.dart`, change the notifications push from:

```dart
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => const NotificationsScreen()),
            ),
```

to:

```dart
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) =>
                    NotificationsScreen(onOrderTap: _openOrderDetails),
              ),
            ),
```

- [ ] **Step 2: Add the new-pickup badge to the bell**

The `build` method already holds `final ordersAsync = ref.watch(ordersStreamProvider);` (≈ line 312). Add, just below it:

```dart
    final newPickupCount = NotificationSummary.fromOrders(
      ordersAsync.valueOrNull ?? const [],
      now: DateTime.now(),
    ).newPickups.length;
```

Then wrap the bell `IconButton` in a `Badge`. Replace:

```dart
          IconButton(
            tooltip: 'Notifications',
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) =>
                    NotificationsScreen(onOrderTap: _openOrderDetails),
              ),
            ),
            icon: const Icon(Icons.notifications_none_rounded),
          ),
```

with:

```dart
          Badge.count(
            count: newPickupCount,
            isLabelVisible: newPickupCount > 0,
            child: IconButton(
              tooltip: 'Notifications',
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) =>
                      NotificationsScreen(onOrderTap: _openOrderDetails),
                ),
              ),
              icon: const Icon(Icons.notifications_none_rounded),
            ),
          ),
```

- [ ] **Step 3: Add the import**

Add to the import block (alphabetically near the other `../notifications/` import on line 8):

```dart
import '../notifications/notification_summary.dart';
```

- [ ] **Step 4: Analyze**

Run: `flutter analyze lib/src/dashboard/staff_dashboard_screen.dart`
Expected: No issues. (If an "unused import" or const-ctor lint fires, resolve it — e.g. the `const NotificationsScreen` removal already drops the old const.)

- [ ] **Step 5: Re-run the notifications test file**

Run: `flutter test test/notifications/notifications_screen_test.dart`
Expected: PASS (3 tests) — confirms the screen still builds with the callback wiring.

- [ ] **Step 6: Commit**

```bash
git add lib/src/dashboard/staff_dashboard_screen.dart
git commit -m "feat(dashboard): open order details from notifications + new-pickup badge"
```

---

## Task 5: Full-suite sanity check

**Files:** none (verification only)

- [ ] **Step 1: Analyze the whole project**

Run: `flutter analyze`
Expected: No new issues introduced by this work.

- [ ] **Step 2: Run each new/changed test file (one at a time — this host hangs on multi-file runs)**

Run:
```bash
flutter test test/notifications/notification_summary_test.dart
flutter test test/notifications/relative_time_test.dart
flutter test test/notifications/notifications_screen_test.dart
```
Expected: All PASS.

- [ ] **Step 3: Final review**

Confirm: no `DateTime.now()` inside the pure helpers; `NotificationsScreen` defaults `clock` to `DateTime.now`; the dashboard badge hides at count 0. No commit needed if Tasks 1-4 were each committed.

---

## Self-Review Notes (author)

- **Spec coverage:** count chips + recent feed (Task 3), new-pickup filter & 48h delivered window (Task 1), relative time (Task 2), `onOrderTap` navigation (Tasks 3-4), bell badge (Task 4), empty state (Task 3), loading/error mirroring the dashboard (Task 3). Ordering open-question resolved (pickups-first) under File Structure.
- **Non-goals honored:** no new repository/table/sync; no stored read/unread; no push; no filtering/muting; no router refactor.
- **Type consistency:** `NotificationSummary.fromOrders(orders, now:)`, `NotificationItem.kind` (`NotificationKind.newPickup`/`delivered`), `relativeTimeLabel(time, now:)`, `kDeliveredWindow` — names match across tasks and tests.
- **Verified against source:** `AppCard.onTap` is `VoidCallback?` and null-safe (inert card). `ServiceType.washAndIron` is a real enum case (alongside `dryCleaning`, `ironOnly`, `washOnly`); its value is irrelevant to these tests. `ProofEvent` requires `id`/`type`/`capturedAt`/`count`/`photoPaths` (`notes` optional) — fixtures match. `ordersStreamProvider` lives in `lib/src/sync/repository_providers.dart`. `_openOrderDetails(LaundryOrder)` is the dashboard's existing handler.
```
