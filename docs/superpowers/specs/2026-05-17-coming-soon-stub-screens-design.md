# Coming-Soon Stub Screens — Design (2026-05-17)

## Status
Draft — pending user review

## Summary
Replace the three "Coming soon" SnackBars on the staff dashboard with real, navigable screens that show a quiet empty state. This unblocks future feature work on **Notifications**, **New pickup**, and **Order search** by establishing each as a real route the rest of the app can push to, instead of dead taps that flash a toast.

This is a routing-and-shell change only. No data model, no backend, no business logic.

## Problem
The dashboard has three controls — the bell `IconButton` in the AppBar, the "New pickup" action button, and the "Check order" action button — whose taps presently call `showComingSoon(context, ...)`. Each shows a 2-second SnackBar and otherwise goes nowhere. As we start building each of the three features, every initial task ("show notification list", "open the new-pickup form", "type into a search box") needs a screen to land on. Today there's nothing to push.

A secondary problem: the SnackBar pattern conflates "this works but the action is queued" (real product feedback) with "this button is dead." Users have no way to know which is which.

## Goal
Each of the three currently-dead controls navigates to a real, named widget with its own AppBar and a quiet empty-state body. The screen makes it obvious the feature isn't built yet without looking broken. Downstream work on each feature can then proceed by replacing the empty-state body in place — no router refactor required.

## Non-Goals
- Any real notifications logic (no list, no model, no push delivery, no read/unread state).
- Any real new-pickup logic (no form, no order creation, no validation).
- Any real search logic (no text field, no filter against existing orders).
- A named-route / `GoRouter` migration. The app currently uses inline `Navigator.push(MaterialPageRoute(...))` and this change keeps that pattern.
- Internationalization / l10n. Copy is hardcoded English to match the rest of the app.
- Re-skinning the dashboard. The three tap sites stay structurally where they are.

## Decisions Locked In
1. **Routing-only stubs** — no mocked-data MVPs. Picked over "skeleton UI" to avoid looking broken and over "MVP with mocks" to keep the change small and YAGNI-clean.
2. **Quiet empty state** in each screen — an icon, a one-line headline, and a one-line subtitle, centered.
3. **Shared `EmptyState` widget** at `lib/src/shared/widgets/empty_state.dart`. Three near-identical screens make the duplication worth extracting; the widget stays private to the package by convention (not exported as part of a public API).
4. **Delete `coming_soon_snackbar.dart`**. After this change it has zero callers. Re-add when a fourth stub appears.
5. **Folder placement** — Notifications gets a new `lib/src/notifications/` directory (no existing home); New pickup and Order search live next to the existing order screens under `lib/src/orders/`.

## File Layout

```
lib/src/
  notifications/
    notifications_screen.dart        (new)
  orders/
    new_pickup_screen.dart           (new)
    order_search_screen.dart         (new)
  shared/widgets/
    empty_state.dart                 (new — shared by all three screens)
    coming_soon_snackbar.dart        (deleted — no remaining callers)
  dashboard/
    staff_dashboard_screen.dart      (modified — 3 callbacks rewired)

test/
  notifications/
    notifications_screen_test.dart   (new)
  orders/
    new_pickup_screen_test.dart      (new)
    order_search_screen_test.dart    (new)
  dashboard/
    staff_dashboard_screen_test.dart (modified — 3 navigation tests added)
```

## Components

### `EmptyState` (`lib/src/shared/widgets/empty_state.dart`)
A `StatelessWidget` taking `IconData icon`, `String headline`, `String subtitle`. Renders the icon (large, subdued) above the headline (bold, dark) above the subtitle (muted), centered vertically and horizontally with reasonable horizontal padding. Uses the existing brand color constants from `app_theme.dart` (`amuwakDark`, `amuwakSoftAccent`).

The widget is intentionally not parameterized beyond those three fields. A future feature replacing the body of one of these screens removes the `EmptyState` call site entirely; the widget itself stays useful for genuinely-empty product states.

### `NotificationsScreen`, `NewPickupScreen`, `OrderSearchScreen`
Each is a `StatelessWidget` with the same structure:

```dart
Scaffold(
  backgroundColor: amuwakBackground,
  appBar: AppBar(
    backgroundColor: amuwakBackground,
    foregroundColor: amuwakDark,
    elevation: 0,
    title: const Text('<feature title>'),
  ),
  body: const EmptyState(
    icon: <icon>,
    headline: '<headline>',
    subtitle: '<subtitle>',
  ),
);
```

The per-screen content:

| Screen | AppBar title | Icon | Headline | Subtitle |
|---|---|---|---|---|
| `NotificationsScreen` | "Notifications" | `Icons.notifications_off_outlined` | "No notifications yet." | "We'll let you know when something needs your attention." |
| `NewPickupScreen` | "New pickup" | `Icons.add_location_alt_outlined` | "New pickup will land here soon." | "For now, pickups come from the dashboard list." |
| `OrderSearchScreen` | "Order search" | `Icons.search_off_rounded` | "Order search coming soon." | "For now, browse orders on the dashboard." |

### Dashboard wiring (`lib/src/dashboard/staff_dashboard_screen.dart`)
Three call sites change from `() => showComingSoon(context, '<feature>')` to `() => Navigator.push(context, MaterialPageRoute(builder: (_) => <FeatureScreen>()))`:

- AppBar bell `IconButton` (currently at line 137) → `NotificationsScreen()`
- "New pickup" `_ActionButton` (currently at line 394) → `NewPickupScreen()`
- "Check order" `_ActionButton` (currently at line 402) → `OrderSearchScreen()`

The `showComingSoon` import line is removed along with the file deletion.

## Testing

### Per-screen tests (three new files)
Each pumps the screen inside a `MaterialApp` and asserts:
- `find.text('<AppBar title>')` finds exactly one widget.
- `find.text('<headline>')` finds exactly one widget.
- `find.byIcon(<icon>)` finds exactly one widget.
- `tester.takeException()` is null (no overflow / build errors).

### Dashboard navigation tests (three additions to existing file)
Each pumps `StaffDashboardScreen` inside a `MaterialApp`, taps one of the three controls, settles, and asserts the new screen widget type is present (`expect(find.byType(NotificationsScreen), findsOneWidget)`, etc.). These replace whatever implicit "shows snackbar" coverage may have lived in manual testing.

### No "coming soon" SnackBars regression test
A search assertion isn't necessary — the codebase no longer contains `showComingSoon` after this PR, and `flutter analyze` will fail if any callsite is left dangling.

## Open Questions
None at this point. All scope and copy decisions are locked above.

## Out of Scope (for follow-up specs)
- Real `NotificationsScreen` — needs a notification model, a delivery channel decision (FCM vs. polling), and read/unread state.
- Real `NewPickupScreen` — needs a customer-picker, a service-type picker, and a write path into the order repository.
- Real `OrderSearchScreen` — needs at minimum a `TextField` filtering the in-memory order list by `orderId` and `customerName`, and likely an empty-results state distinct from the initial empty state shipped here.

Each of these warrants its own spec when picked up.
