# Coming-Soon Stub Screens Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the three "Coming soon" SnackBars on the staff dashboard with real, navigable screens that show a quiet empty state, so future feature work has somewhere to land.

**Architecture:** Three new `StatelessWidget` screens (Notifications, New pickup, Order search) share one new `EmptyState` widget. The dashboard rewires its three coming-soon callbacks to `Navigator.push` of the matching screen. The now-dead `coming_soon_snackbar.dart` helper is deleted. No data model, no router refactor.

**Tech Stack:** Flutter (Dart `^3.8.0`), `flutter_test`. Reuses existing brand tokens from [lib/src/shared/widgets/app_theme.dart](lib/src/shared/widgets/app_theme.dart) (`amuwakBackground`, `amuwakDark`, `amuwakSoftAccent`).

**Spec:** [docs/superpowers/specs/2026-05-17-coming-soon-stub-screens-design.md](docs/superpowers/specs/2026-05-17-coming-soon-stub-screens-design.md)

---

## File map

```
lib/src/
  notifications/
    notifications_screen.dart        (Task 2 — new)
  orders/
    new_pickup_screen.dart           (Task 3 — new)
    order_search_screen.dart         (Task 4 — new)
  shared/widgets/
    empty_state.dart                 (Task 1 — new, shared by all three screens)
    coming_soon_snackbar.dart        (Task 5 — deleted)
  dashboard/
    staff_dashboard_screen.dart      (Task 5 — three callbacks rewired, import removed)

test/
  notifications/
    notifications_screen_test.dart   (Task 2 — new)
  orders/
    new_pickup_screen_test.dart      (Task 3 — new)
    order_search_screen_test.dart    (Task 4 — new)
  shared/widgets/
    empty_state_test.dart            (Task 1 — new)
  dashboard/
    staff_dashboard_screen_test.dart (Task 5 — three navigation tests added)
```

Each task ends in a single commit. Five tasks total, five commits.

---

### Task 1: Shared `EmptyState` widget

**Files:**
- Create: `lib/src/shared/widgets/empty_state.dart`
- Test: `test/shared/widgets/empty_state_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/shared/widgets/empty_state_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_staff/src/shared/widgets/empty_state.dart';

void main() {
  testWidgets('EmptyState renders the icon, headline, and subtitle',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EmptyState(
            icon: Icons.inbox_outlined,
            headline: 'Nothing here.',
            subtitle: 'Check back later.',
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);
    expect(find.text('Nothing here.'), findsOneWidget);
    expect(find.text('Check back later.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 2: Run the test and verify it fails**

Run: `flutter test test/shared/widgets/empty_state_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:amuwak_staff/src/shared/widgets/empty_state.dart'`.

- [ ] **Step 3: Write the widget**

Create `lib/src/shared/widgets/empty_state.dart`:

```dart
import 'package:flutter/material.dart';

import 'app_theme.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.headline,
    required this.subtitle,
  });

  final IconData icon;
  final String headline;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 72, color: amuwakSoftAccent),
            const SizedBox(height: 16),
            Text(
              headline,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: amuwakDark,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the test and verify it passes**

Run: `flutter test test/shared/widgets/empty_state_test.dart`
Expected: PASS — `+1: All tests passed!`

- [ ] **Step 5: Run analyzer**

Run: `flutter analyze lib/src/shared/widgets/empty_state.dart test/shared/widgets/empty_state_test.dart`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/src/shared/widgets/empty_state.dart test/shared/widgets/empty_state_test.dart
git commit -m "Add EmptyState shared widget for placeholder screens

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: `NotificationsScreen`

**Files:**
- Create: `lib/src/notifications/notifications_screen.dart`
- Test: `test/notifications/notifications_screen_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/notifications/notifications_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_staff/src/notifications/notifications_screen.dart';

void main() {
  testWidgets('NotificationsScreen shows the empty state', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: NotificationsScreen()),
    );

    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('No notifications yet.'), findsOneWidget);
    expect(
      find.text("We'll let you know when something needs your attention."),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.notifications_off_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 2: Run the test and verify it fails**

Run: `flutter test test/notifications/notifications_screen_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:amuwak_staff/src/notifications/notifications_screen.dart'`.

- [ ] **Step 3: Write the screen**

Create `lib/src/notifications/notifications_screen.dart`:

```dart
import 'package:flutter/material.dart';

import '../shared/widgets/app_theme.dart';
import '../shared/widgets/empty_state.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: amuwakBackground,
      appBar: AppBar(
        backgroundColor: amuwakBackground,
        foregroundColor: amuwakDark,
        elevation: 0,
        title: const Text('Notifications'),
      ),
      body: const EmptyState(
        icon: Icons.notifications_off_outlined,
        headline: 'No notifications yet.',
        subtitle: "We'll let you know when something needs your attention.",
      ),
    );
  }
}
```

- [ ] **Step 4: Run the test and verify it passes**

Run: `flutter test test/notifications/notifications_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Run analyzer**

Run: `flutter analyze lib/src/notifications/ test/notifications/`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/src/notifications/notifications_screen.dart test/notifications/notifications_screen_test.dart
git commit -m "Add NotificationsScreen placeholder

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: `NewPickupScreen`

**Files:**
- Create: `lib/src/orders/new_pickup_screen.dart`
- Test: `test/orders/new_pickup_screen_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/orders/new_pickup_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_staff/src/orders/new_pickup_screen.dart';

void main() {
  testWidgets('NewPickupScreen shows the empty state', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: NewPickupScreen()),
    );

    expect(find.text('New pickup'), findsOneWidget);
    expect(find.text('New pickup will land here soon.'), findsOneWidget);
    expect(
      find.text('For now, pickups come from the dashboard list.'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.add_location_alt_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 2: Run the test and verify it fails**

Run: `flutter test test/orders/new_pickup_screen_test.dart`
Expected: FAIL — URI does not exist.

- [ ] **Step 3: Write the screen**

Create `lib/src/orders/new_pickup_screen.dart`:

```dart
import 'package:flutter/material.dart';

import '../shared/widgets/app_theme.dart';
import '../shared/widgets/empty_state.dart';

class NewPickupScreen extends StatelessWidget {
  const NewPickupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: amuwakBackground,
      appBar: AppBar(
        backgroundColor: amuwakBackground,
        foregroundColor: amuwakDark,
        elevation: 0,
        title: const Text('New pickup'),
      ),
      body: const EmptyState(
        icon: Icons.add_location_alt_outlined,
        headline: 'New pickup will land here soon.',
        subtitle: 'For now, pickups come from the dashboard list.',
      ),
    );
  }
}
```

- [ ] **Step 4: Run the test and verify it passes**

Run: `flutter test test/orders/new_pickup_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Run analyzer**

Run: `flutter analyze lib/src/orders/new_pickup_screen.dart test/orders/new_pickup_screen_test.dart`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/src/orders/new_pickup_screen.dart test/orders/new_pickup_screen_test.dart
git commit -m "Add NewPickupScreen placeholder

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: `OrderSearchScreen`

**Files:**
- Create: `lib/src/orders/order_search_screen.dart`
- Test: `test/orders/order_search_screen_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/orders/order_search_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_staff/src/orders/order_search_screen.dart';

void main() {
  testWidgets('OrderSearchScreen shows the empty state', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: OrderSearchScreen()),
    );

    expect(find.text('Order search'), findsOneWidget);
    expect(find.text('Order search coming soon.'), findsOneWidget);
    expect(
      find.text('For now, browse orders on the dashboard.'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.search_off_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 2: Run the test and verify it fails**

Run: `flutter test test/orders/order_search_screen_test.dart`
Expected: FAIL — URI does not exist.

- [ ] **Step 3: Write the screen**

Create `lib/src/orders/order_search_screen.dart`:

```dart
import 'package:flutter/material.dart';

import '../shared/widgets/app_theme.dart';
import '../shared/widgets/empty_state.dart';

class OrderSearchScreen extends StatelessWidget {
  const OrderSearchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: amuwakBackground,
      appBar: AppBar(
        backgroundColor: amuwakBackground,
        foregroundColor: amuwakDark,
        elevation: 0,
        title: const Text('Order search'),
      ),
      body: const EmptyState(
        icon: Icons.search_off_rounded,
        headline: 'Order search coming soon.',
        subtitle: 'For now, browse orders on the dashboard.',
      ),
    );
  }
}
```

- [ ] **Step 4: Run the test and verify it passes**

Run: `flutter test test/orders/order_search_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Run analyzer**

Run: `flutter analyze lib/src/orders/order_search_screen.dart test/orders/order_search_screen_test.dart`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/src/orders/order_search_screen.dart test/orders/order_search_screen_test.dart
git commit -m "Add OrderSearchScreen placeholder

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Rewire the dashboard, delete the snackbar helper

**Files:**
- Modify: `lib/src/dashboard/staff_dashboard_screen.dart`
- Delete: `lib/src/shared/widgets/coming_soon_snackbar.dart`
- Modify: `test/dashboard/staff_dashboard_screen_test.dart`

Before starting, locate the three current callsites in the dashboard. Lines may have drifted since the spec was written:

```bash
grep -n 'showComingSoon' lib/src/dashboard/staff_dashboard_screen.dart
```

Expect three matches: the bell `IconButton` (`onPressed`), the "New pickup" `_ActionButton` (`onTap`), and the "Check order" `_ActionButton` (`onTap`).

- [ ] **Step 1: Write the failing dashboard navigation tests**

Open `test/dashboard/staff_dashboard_screen_test.dart` and append the three tests below inside the existing `main() { ... }` block (after the existing `Does not show the lost-capture SnackBar when nothing was lost` test, before the final `}`). Also add the four imports at the top — keep them grouped with existing `package:amuwak_staff/...` imports.

New imports at the top of the file:

```dart
import 'package:amuwak_staff/src/notifications/notifications_screen.dart';
import 'package:amuwak_staff/src/orders/new_pickup_screen.dart';
import 'package:amuwak_staff/src/orders/order_search_screen.dart';
```

New tests appended inside `main`:

```dart
  testWidgets(
    'Tapping the bell opens NotificationsScreen',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: StaffDashboardScreen(
            retrieveLostPhoto: () async => false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Notifications'));
      await tester.pumpAndSettle();

      expect(find.byType(NotificationsScreen), findsOneWidget);
    },
  );

  testWidgets(
    'Tapping "New pickup" opens NewPickupScreen',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: StaffDashboardScreen(
            retrieveLostPhoto: () async => false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('New pickup'));
      await tester.pumpAndSettle();

      expect(find.byType(NewPickupScreen), findsOneWidget);
    },
  );

  testWidgets(
    'Tapping "Check order" opens OrderSearchScreen',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: StaffDashboardScreen(
            retrieveLostPhoto: () async => false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Check order'));
      await tester.pumpAndSettle();

      expect(find.byType(OrderSearchScreen), findsOneWidget);
    },
  );
```

- [ ] **Step 2: Run the dashboard tests and verify the three new ones fail**

Run: `flutter test test/dashboard/staff_dashboard_screen_test.dart`
Expected: the two original tests pass; the three new tests FAIL with `Expected: exactly one matching candidate, Actual: Found 0 widgets` (the SnackBar fires instead of a navigation).

- [ ] **Step 3: Add the three new screen imports to the dashboard**

In `lib/src/dashboard/staff_dashboard_screen.dart`, find the existing `import` block at the top of the file. Add these three imports alongside the other `../orders/...` and `../shared/...` lines:

```dart
import '../notifications/notifications_screen.dart';
import '../orders/new_pickup_screen.dart';
import '../orders/order_search_screen.dart';
```

Then **delete** this existing line from the same block:

```dart
import '../shared/widgets/coming_soon_snackbar.dart';
```

- [ ] **Step 4: Rewire the three callbacks**

Locate each `showComingSoon(...)` call (use grep — line numbers as of this writing are 176, 433, 441, but may have drifted) and replace each in-place:

**Bell IconButton** — currently:
```dart
onPressed: () => showComingSoon(context, 'Notifications'),
```
becomes:
```dart
onPressed: () => Navigator.of(context).push<void>(
  MaterialPageRoute(builder: (_) => const NotificationsScreen()),
),
```

**"New pickup" `_ActionButton`** — currently:
```dart
onTap: () => showComingSoon(context, 'New pickup'),
```
becomes:
```dart
onTap: () => Navigator.of(context).push<void>(
  MaterialPageRoute(builder: (_) => const NewPickupScreen()),
),
```

**"Check order" `_ActionButton`** — currently:
```dart
onTap: () => showComingSoon(context, 'Order search'),
```
becomes:
```dart
onTap: () => Navigator.of(context).push<void>(
  MaterialPageRoute(builder: (_) => const OrderSearchScreen()),
),
```

- [ ] **Step 5: Delete the now-dead snackbar helper**

```bash
git rm lib/src/shared/widgets/coming_soon_snackbar.dart
```

(Use `git rm`, not plain `rm` — this both removes the file and stages the deletion.)

- [ ] **Step 6: Run the dashboard tests and verify they pass**

Run: `flutter test test/dashboard/staff_dashboard_screen_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 7: Run the full test suite**

Run: `flutter test`
Expected: all tests pass. No regressions from removed import or screen wiring.

- [ ] **Step 8: Run the analyzer**

Run: `flutter analyze`
Expected: `No issues found!` — confirms no leftover `showComingSoon` references and no unused imports.

- [ ] **Step 9: Commit**

```bash
git add lib/src/dashboard/staff_dashboard_screen.dart test/dashboard/staff_dashboard_screen_test.dart
git commit -m "Route the three coming-soon taps to real placeholder screens

Replaces the showComingSoon SnackBars on the dashboard with
Navigator.push of NotificationsScreen, NewPickupScreen, and
OrderSearchScreen. Removes the now-dead coming_soon_snackbar helper.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Post-execution checklist

After Task 5:

- [ ] `flutter test` is fully green.
- [ ] `flutter analyze` reports no issues.
- [ ] `grep -r 'showComingSoon' lib/ test/` returns no matches.
- [ ] `git log --oneline -5` shows the five new commits stacked on the branch tip.
- [ ] `git status` shows no unintended modifications outside the files in the file map above (the pre-existing untracked `.claude/`, `.vscode/`, and modified flutter `generated_plugin_*` files are unrelated and expected).
