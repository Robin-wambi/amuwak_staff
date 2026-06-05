# Notifications Page — Design (2026-06-05)

## Status
Draft — pending user review

## Summary
Replace the static placeholder `NotificationsScreen` with a real, useful **summary** of two things a rider cares about: **new pickup orders** awaiting collection, and **recently delivered orders** (rolling 48-hour window). Both are derived — in a pure, unit-testable helper — from the orders the app is already streaming via `ordersStreamProvider`. No new repository, table, sync code, or backend change.

The layout is "Option C": two **count chips** at the top (New pickups · Delivered·48h) over a single merged **Recent** feed of tappable rows. Tapping a row opens the existing `OrderDetailsScreen` through the same `onOrderTap` callback `OrderSearchScreen` already uses. The dashboard AppBar bell gains a small **badge** showing the new-pickup count.

## Problem
The Notifications page today (`lib/src/notifications/notifications_screen.dart`) is a hard-coded `EmptyState` — "No notifications yet." There is no notification model and nothing behind it. A rider opening it learns nothing. Meanwhile the two pieces of information most worth surfacing at a glance — *what do I still need to pick up* and *what did I just deliver* — already exist in the live orders stream but are only visible by scanning the full dashboard order list and filtering by status in your head.

## Goal
- A rider opens Notifications and immediately sees **how many new pickups** are waiting and **how many orders were delivered** in the last 48 hours.
- Below the counts, a **Recent** feed lists the actual orders (icon · order code · customer · area · time), newest activity first, each tappable to open Order Details.
- The page updates **reactively** — it watches the same live `ordersStreamProvider` as the dashboard, so a new pickup or a delivery shows up without a manual refresh.
- The dashboard **bell icon shows a badge** equal to the new-pickup count, so the rider knows there is something worth opening.
- When there are no new pickups and nothing delivered in the window, the existing **empty state** is shown.

## Non-Goals
- **No new notification model / table / read-state persistence.** v1 is a derived *summary*, not a stored notification inbox. There is no per-item read/unread, no mark-as-read, no dismiss, no history beyond the rolling window. (The badge reflects a live count, not unread state.)
- **No new event sources.** Only new pickups and delivered orders. Sync failures, order issues, overdue alerts, and connectivity events — discussed during brainstorming — are explicitly out of scope for this version.
- **No push / local OS notifications.** This is an in-app summary screen only.
- **No filtering, muting, snoozing, or preferences UI.**
- **No router refactor.** The screen stays pushed via `Navigator.push(MaterialPageRoute(...))`, matching the dashboard's existing pattern.
- **No grouping/section headers in the feed beyond the visual count chips.** The Recent list is one merged, time-ordered list; row type is conveyed by icon + label.

## Decisions Locked In
1. **Data source is the existing `ordersStreamProvider`.** `NotificationsScreen` changes from `StatelessWidget` to a Riverpod `ConsumerWidget` and watches that provider. No new repository.
2. **"New pickups" = orders with status `OrderStatus.pendingPickup`.**
3. **"Delivered" = orders that have a delivery proof event (`ProofEventType.delivery`) whose `capturedAt` is within the last 48 hours.** The delivery proof event is the true "delivered" moment and carries an accurate timestamp for the rolling window — preferred over the terminal `completed` status, which has no exposed timestamp on the `LaundryOrder` model.
4. **Rolling window = 48 hours**, expressed as a single named constant so it is trivial to change.
5. **Derivation is a pure function**, e.g. `NotificationSummary.fromOrders(List<LaundryOrder> orders, {required DateTime now})`, returning the two lists + counts. The injected `now` is the testability seam (mirrors the `clock` pattern already used in `OrdersRepository`). No `DateTime.now()` inside widgets.
6. **Recent feed ordering:** merged list of (new-pickup rows + delivered rows) sorted by their relevant timestamp descending — delivered rows by `capturedAt`, new-pickup rows by `scheduledFor` (falling back to a stable order when null). Final ordering rule to be pinned in the plan; the principle is "most recent / most imminent first."
7. **Navigation reuses `onOrderTap`.** `NotificationsScreen` takes an `void Function(LaundryOrder)? onOrderTap` constructor param; the dashboard passes its existing `_openOrderDetails`, exactly as it already does for `OrderSearchScreen`. The screen does not take the photo/camera/repo dependencies directly.
8. **Bell badge = new-pickup count.** The dashboard AppBar `IconButton` wraps its icon in a badge driven by the same derived count (read from `ordersStreamProvider`), shown only when count > 0.
9. **Empty state reused** (`EmptyState`, `Icons.notifications_off_outlined`) when both derived lists are empty. The existing empty-state copy is kept.

## Architecture & Components

### New / changed units
- **`NotificationSummary` (new, pure model + factory).** Holds `newPickups`, `delivered`, and the merged `recent` list (or exposes counts). `NotificationSummary.fromOrders(orders, now: ...)` does all filtering/sorting. Lives under `lib/src/notifications/`. Pure Dart, no Flutter — directly unit-testable.
- **`NotificationsScreen` (rewritten).** `ConsumerWidget`; watches `ordersStreamProvider`, builds a `NotificationSummary`, renders: count chips → "Recent" feed → empty state fallback. Accepts `onOrderTap`.
- **Notification row widget(s)** for a feed item (icon chip, code, customer · area, relative time, chevron). May reuse/share styling primitives from the existing `order_card` widgets and theme (`app_card`, `status_colors`, `app_spacing`).
- **Dashboard AppBar bell badge (small edit in `staff_dashboard_screen.dart`).** Wrap the existing notifications `IconButton` icon in a badge bound to the new-pickup count; pass `_openOrderDetails` into `NotificationsScreen`.

### Data flow
`ordersStreamProvider` (live Supabase orders) → `NotificationsScreen` watches → `NotificationSummary.fromOrders(orders, now)` → two count chips + merged Recent feed → row tap → `onOrderTap(order)` → dashboard's `_openOrderDetails` → `OrderDetailsScreen`. Same stream re-emits on any order change, so counts and feed stay live. The bell badge reads the same provider/count.

### Relative-time formatting
Feed timestamps render as relative labels ("4 min ago", "scheduled 9:30 AM"). Formatting is a small pure helper taking `now` (same seam as the summary), so it is testable and consistent with the rest of the app's time display.

## Error / Edge Handling
- **Stream loading / error:** mirror the dashboard — show loading and an error+retry (`ref.invalidate(ordersStreamProvider)`) using the same `AsyncValue.when` pattern already in `staff_dashboard_screen.dart`, rather than a bespoke treatment.
- **Both lists empty:** existing `EmptyState`.
- **Delivered order missing a delivery proof timestamp:** excluded from the delivered window (by definition it has no `capturedAt` to place in the window).
- **New pickup with null `scheduledFor`:** still counted and listed; ordered last among new pickups / by a stable fallback so the list is deterministic.
- **Badge:** hidden when count is 0; no number shown.

## Testing
- **`NotificationSummary.fromOrders` unit tests (pure, no widgets):** new-pickup filtering; delivered-within-48h inclusion/exclusion at the boundary (just-inside vs just-outside, using injected `now`); ordering (newest delivered first, imminent pickups, null `scheduledFor` fallback); empty input.
- **Relative-time helper unit tests** with injected `now`.
- **`NotificationsScreen` widget tests:** count chips render the right numbers; Recent rows render code/customer/time; tapping a row invokes `onOrderTap` with the right order; empty state shows when no pickups and nothing delivered; loading/error states render.
- **Update the existing placeholder test** (`test/notifications/notifications_screen_test.dart`) — its current assertions (empty-state-only) become the empty-input case; add the populated cases.
- Run single-file `flutter test` invocations (this Windows host hangs on multi-file runs).

## Open Questions (defaults chosen; confirm on review)
- Rolling window **48h** vs 24h — defaulted to 48h.
- "Delivered" by **delivery proof event** vs `completed` status — defaulted to proof event.
- Exact merged-feed ordering rule when mixing pickups (future scheduled time) and deliveries (past capture time) — to be pinned in the implementation plan.
