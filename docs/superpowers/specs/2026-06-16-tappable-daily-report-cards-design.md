# Tappable daily-report summary cards

**Date:** 2026-06-16
**Branch:** feat/daily-report-revenue

## Goal

Make the four summary cards on the Daily report screen — **Orders**, **Items**,
**Completed**, **Pending work** — tappable, each opening into its own page.

## Context

The cards live in `DailyReportView` ([daily_report_screen.dart](../../../lib/src/reports/daily_report_screen.dart)),
rendered as `_ReportMetricCard`s. In production the report is reached only via
the dashboard's **Report tab** ([staff_dashboard_screen.dart:418](../../../lib/src/dashboard/staff_dashboard_screen.dart#L418)),
which renders `DailyReportView` directly. The standalone `DailyReportScreen` is
used only by tests.

The app already has a proven pattern for tappable summary cards: the dashboard
home cards (PR #53) open an [OrderFilterScreen](../../../lib/src/orders/order_filter_screen.dart) —
a read-only, date-grouped order list driven by an [OrderFilter](../../../lib/src/orders/order_filter.dart).
A single `OrderFilter` is the source of truth for both a card's count and the
list it opens, so the two can never disagree.

The four report cards map onto this as:

| Card         | Meaning                          | Opens                          |
|--------------|----------------------------------|--------------------------------|
| Orders       | All assigned orders              | `OrderFilterScreen(all)`       |
| Completed    | All completed orders (all-time)  | `OrderFilterScreen(completed)` |
| Pending work | Orders not yet completed         | `OrderFilterScreen(pendingWork)` |
| Items        | Count of items (not an order subset) | `ItemsBreakdownScreen` (new) |

## Design decisions

- **Reuse `OrderFilterScreen`** for Orders / Completed / Pending work — consistent
  UX, count-equals-list invariant, least new code.
- **Items gets a dedicated breakdown page** because it counts items, not orders,
  so it has no natural order subset. Rows are ordered **most-items-first** and
  are tappable into order details.
- **Navigation via optional callbacks.** `DailyReportView` gains optional
  callbacks (mirroring how `_HomeTab` already takes `onOpenFiltered`). Cards stay
  non-tappable when a callback isn't supplied, so the existing standalone/test
  render path keeps working unchanged.

## Components

### 1. `OrderFilter` — two new values

File: [order_filter.dart](../../../lib/src/orders/order_filter.dart)

- `completed` — `o.status == OrderStatus.completed` (all-time, distinct from the
  existing `completedToday`). Label `"Completed"`. `newestFirst: true` (completed
  work reads most-recent-first).
- `pendingWork` — `o.status != OrderStatus.completed`. Label `"Pending work"`.
  `newestFirst: false` (upcoming work reads soonest-first).

The enum's exhaustive switches (`label`, `newestFirst`, `matches`) force both
values to be handled. Adding values does **not** affect the dashboard grid, which
hardcodes the filters it shows. No other exhaustive switch over `OrderFilter`
exists outside the enum (verify during implementation).

### 2. `DailyReportView` / `_ReportMetricCard` taps

File: [daily_report_screen.dart](../../../lib/src/reports/daily_report_screen.dart)

- `DailyReportView` gains optional `void Function(OrderFilter)? onOpenFiltered`
  and `void Function()? onOpenItems`.
- `_ReportMetricCard` gains an optional `VoidCallback? onTap`, rendered through
  `AppCard(onTap:)` (already supported — see `_AccountTab`).
- Wiring:
  - Orders → `onOpenFiltered?.call(OrderFilter.all)`
  - Completed → `onOpenFiltered?.call(OrderFilter.completed)`
  - Pending work → `onOpenFiltered?.call(OrderFilter.pendingWork)`
  - Items → `onOpenItems?.call()`
- A card is only tappable when its relevant callback is non-null.
- Card counts/values are unchanged; they already equal the new filters' counts by
  construction, preserving the invariant.

### 3. `ItemsBreakdownScreen` (new)

File: `lib/src/reports/items_breakdown_screen.dart` (new)

- A `ConsumerWidget` watching `ordersStreamProvider` (same live-list behaviour as
  `OrderFilterScreen`).
- Body: orders that contributed items, ordered **most-items-first**, each row
  reusing `OrderCard` and tappable via an injected `onOrderTap` callback.
- A header shows the day's total items handled.
- Loading / error / empty states follow `OrderFilterScreen`'s `EmptyState`
  convention.
- Takes `void Function(LaundryOrder) onOrderTap` and an optional injectable
  clock if needed for any date display (consistent with `OrderFilterScreen`).

### 4. Dashboard wiring

File: [staff_dashboard_screen.dart](../../../lib/src/dashboard/staff_dashboard_screen.dart)

- The Report tab (`DailyReportView`, line ~418) passes
  `onOpenFiltered: _openFilteredOrders` (already exists; works for the new
  filters) and `onOpenItems: _openItemsBreakdown`.
- New `_openItemsBreakdown()` pushes
  `ItemsBreakdownScreen(onOrderTap: _openOrderDetails)`.

## Testing (TDD, one commit per task)

- `test/orders/order_filter_test.dart`: `matches`, `label`, `newestFirst`, and
  `count` for `completed` and `pendingWork`.
- `test/reports/daily_report_screen_test.dart`: each card invokes the correct
  callback with the correct argument; cards are inert when callbacks are null.
- `test/reports/items_breakdown_screen_test.dart`: orders rendered
  most-items-first, total-items header present, row tap fires `onOrderTap`, empty
  state when there are no items.
- `test/dashboard/staff_dashboard_screen_test.dart`: report-tab cards navigate
  (light integration check).

## Out of scope

- No change to card counts/values or the report's data scope.
- No offline-path changes.
- No new list UX beyond the Items breakdown page.
