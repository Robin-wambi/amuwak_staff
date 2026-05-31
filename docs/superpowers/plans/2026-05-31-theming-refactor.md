# Theming Refactor (light mode) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Material 3 theme the single source of truth for color, type, spacing, radius, card styling, and order-status colors — so screens stop hardcoding raw colors/sizes — and fix the status-chip WCAG contrast bug. Light mode only; no dark theme.

**Architecture:** Add a `lib/src/shared/theme/` design-system folder (const token classes for spacing/radii, a `StatusColors` `ThemeExtension`, an `AppCard` widget) and rewrite `lib/src/shared/widgets/app_theme.dart` to assemble them into `ThemeData`. Migrate call sites bottom-up so every commit compiles and tests stay green.

**Tech Stack:** Flutter 3.32.0 (stable), Dart SDK ^3.8.0, Riverpod, `flutter_test`. Package name: `amuwak_staff`.

**Spec:** `docs/superpowers/specs/2026-05-31-theming-refactor-design.md`

**Host constraint:** This Windows host hangs when `flutter test` is given multiple files. Run **one test file per invocation** (e.g. `flutter test test/shared/theme/status_colors_test.dart`).

**Test path convention:** the `test/` tree mirrors `lib/src/` **without** a `src/` segment — e.g. `lib/src/orders/order_status.dart` → `test/orders/order_status_test.dart`, `lib/src/shared/widgets/app_theme.dart` → `test/shared/widgets/app_theme_test.dart`. New theme tests go under `test/shared/theme/`.

---

## File Structure

**New files:**
- `lib/src/shared/theme/app_colors.dart` — brand palette + new semantic constants (`secondaryText`, `cardBorder`).
- `lib/src/shared/theme/app_spacing.dart` — const spacing scale.
- `lib/src/shared/theme/app_radii.dart` — const radius scale.
- `lib/src/shared/theme/status_colors.dart` — `StatusColors` `ThemeExtension` + WCAG contrast helper.
- `lib/src/shared/theme/app_card.dart` — `AppCard` widget over Material `Card`.
- `test/shared/theme/status_colors_test.dart` — mapping + contrast tests.
- `test/shared/theme/app_card_test.dart` — AppCard widget test.
- `test/shared/widgets/app_theme_test.dart` — theme-builder unit test.

**Modified files:**
- `lib/src/shared/widgets/app_theme.dart` — rewritten assembler.
- `lib/src/orders/order_status.dart` — drop `color` field from enum.
- `lib/src/orders/order_details_screen.dart` — status call site (:202, :236), `_StatusChip` (:436), card BoxDecorations.
- `lib/src/dashboard/staff_dashboard_screen.dart` — status call site (:977), `_StatusChip` (:1046), `_OrderCard` + card BoxDecorations.
- `lib/src/reports/daily_report_screen.dart` — card BoxDecorations, inline colors/fontSize.
- `lib/src/auth/login_screen.dart` — inline colors/fontSize.
- `lib/src/orders/proof/pickup_capture_screen.dart`, `delivery_capture_screen.dart` — card BoxDecorations.
- `lib/src/shared/widgets/sync_status_banner.dart` — banner colors via StatusColors.
- `test/orders/order_status_test.dart` — remove any `color` assertions (none currently, but verify).

---

## Task 1: Spacing & radius token classes

**Files:**
- Create: `lib/src/shared/theme/app_spacing.dart`
- Create: `lib/src/shared/theme/app_radii.dart`
- Test: `test/shared/theme/tokens_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/shared/theme/tokens_test.dart`:

```dart
import 'package:amuwak_staff/src/shared/theme/app_radii.dart';
import 'package:amuwak_staff/src/shared/theme/app_spacing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AppSpacing exposes an ascending 4-based scale', () {
    expect(AppSpacing.xs, 4);
    expect(AppSpacing.sm, 8);
    expect(AppSpacing.md, 12);
    expect(AppSpacing.lg, 16);
    expect(AppSpacing.xl, 20);
    expect(AppSpacing.xxl, 24);
  });

  test('AppRadii exposes field/card/chip radii', () {
    expect(AppRadii.field, 18);
    expect(AppRadii.card, 22);
    expect(AppRadii.chip, 999);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/shared/theme/tokens_test.dart`
Expected: FAIL — "Target of URI doesn't exist" (files not created).

- [ ] **Step 3: Write minimal implementation**

Create `lib/src/shared/theme/app_spacing.dart`:

```dart
/// Spacing scale (logical pixels). Use instead of magic-number SizedBox/padding.
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
}
```

Create `lib/src/shared/theme/app_radii.dart`:

```dart
/// Corner-radius scale. Use instead of magic-number BorderRadius.circular(...).
abstract final class AppRadii {
  static const double field = 18;
  static const double card = 22;
  static const double chip = 999;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/shared/theme/tokens_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/src/shared/theme/app_spacing.dart lib/src/shared/theme/app_radii.dart test/shared/theme/tokens_test.dart
git commit -m "feat(theme): add spacing and radius token scales"
```

---

## Task 2: App color palette

**Files:**
- Create: `lib/src/shared/theme/app_colors.dart`
- Test: `test/shared/theme/app_colors_test.dart`

Moves the brand constants out of `app_theme.dart` into one palette file and adds the two semantic constants the screen sweep needs. `app_theme.dart` will re-import these in Task 6 (until then it keeps its own copies, so nothing breaks).

- [ ] **Step 1: Write the failing test**

Create `test/shared/theme/app_colors_test.dart`:

```dart
import 'dart:ui';

import 'package:amuwak_staff/src/shared/theme/app_colors.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AppColors keeps the established brand palette values', () {
    expect(AppColors.primary, const Color(0xFFFF6E11));
    expect(AppColors.surfaceBrand, const Color(0xFFC75A0E));
    expect(AppColors.dark, const Color(0xFF1F1F1F));
    expect(AppColors.background, const Color(0xFFFFF8F2));
    expect(AppColors.white, const Color(0xFFFFFFFF));
  });

  test('AppColors adds semantic constants for the screen sweep', () {
    // Secondary text replaces ad hoc Colors.black54 usage.
    expect(AppColors.secondaryText, isA<Color>());
    // Card hairline replaces the repeated primary @18% border.
    expect(AppColors.cardBorder, isA<Color>());
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/shared/theme/app_colors_test.dart`
Expected: FAIL — URI doesn't exist.

- [ ] **Step 3: Write minimal implementation**

Create `lib/src/shared/theme/app_colors.dart`:

```dart
import 'package:flutter/material.dart';

/// Single source of brand and semantic colors. Light theme only.
abstract final class AppColors {
  // Brand palette (60-30-10 roles).
  static const Color primary = Color(0xFFFF6E11); // logo orange (60%)
  static const Color surfaceBrand = Color(0xFFC75A0E); // deep terracotta (30%)
  static const Color dark = Color(0xFF1F1F1F);
  static const Color background = Color(0xFFFFF8F2);
  static const Color white = Color(0xFFFFFFFF);

  // Semantic constants for values currently hardcoded inline across screens.
  /// Muted body/secondary text. Replaces ad hoc `Colors.black54`.
  static const Color secondaryText = Color(0x99000000); // black @ 60%
  /// Hairline border for cards. Replaces `primary.withValues(alpha: 0.18)`.
  static const Color cardBorder = Color(0x2EFF6E11); // primary @ ~18%
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/shared/theme/app_colors_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/src/shared/theme/app_colors.dart test/shared/theme/app_colors_test.dart
git commit -m "feat(theme): add centralized AppColors palette"
```

---

## Task 3: StatusColors ThemeExtension + contrast guard

**Files:**
- Create: `lib/src/shared/theme/status_colors.dart`
- Test: `test/shared/theme/status_colors_test.dart`

`StatusColors` maps each `OrderStatus` to a `(color, onColor)` pair. `color` is the saturated status hue (for the dot/border); `onColor` is the text color used on the 12%-alpha chip tint and is chosen to pass WCAG 4.5:1 against that tint. This task does NOT yet touch the enum or screens — it only adds the extension and its tests.

The chip tint is `color.withValues(alpha: 0.12)` composited over the white card surface. The test composites that over white before measuring contrast (alpha blending), matching what renders.

- [ ] **Step 1: Write the failing test**

Create `test/shared/theme/status_colors_test.dart`:

```dart
import 'dart:ui';

import 'package:amuwak_staff/src/orders/order_status.dart';
import 'package:amuwak_staff/src/shared/theme/status_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Composite a possibly-translucent foreground over an opaque background.
Color _composite(Color fg, Color bg) {
  final a = fg.a;
  return Color.from(
    alpha: 1,
    red: fg.r * a + bg.r * (1 - a),
    green: fg.g * a + bg.g * (1 - a),
    blue: fg.b * a + bg.b * (1 - a),
  );
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  const status = StatusColors.light;

  test('of() returns a pair for every OrderStatus', () {
    for (final s in OrderStatus.values) {
      final pair = status.of(s);
      expect(pair.color, isA<Color>());
      expect(pair.onColor, isA<Color>());
    }
  });

  test('chip text passes WCAG 4.5:1 on its tinted background', () {
    const surface = Color(0xFFFFFFFF);
    for (final s in OrderStatus.values) {
      final pair = status.of(s);
      final tint = _composite(pair.color.withValues(alpha: 0.12), surface);
      final ratio = _contrast(pair.onColor, tint);
      expect(ratio, greaterThanOrEqualTo(4.5),
          reason: '${s.name} chip contrast was $ratio');
    }
  });

  test('lerp returns a StatusColors and is identity at t=0', () {
    final lerped = status.lerp(status, 0) as StatusColors;
    expect(lerped.of(OrderStatus.completed).color,
        status.of(OrderStatus.completed).color);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/shared/theme/status_colors_test.dart`
Expected: FAIL — `status_colors.dart` URI doesn't exist.

- [ ] **Step 3: Write minimal implementation**

Create `lib/src/shared/theme/status_colors.dart`:

```dart
import 'package:flutter/material.dart';

import '../../orders/order_status.dart';

/// A status color and the text color to render on its tinted chip background.
@immutable
class StatusColorPair {
  const StatusColorPair(this.color, this.onColor);
  final Color color;
  final Color onColor;
}

/// Theme extension holding order-status colors so screens resolve them from the
/// theme instead of hardcoding hex. `onColor` is verified to pass WCAG 4.5:1 on
/// the chip's 12%-alpha tint (see status_colors_test.dart).
@immutable
class StatusColors extends ThemeExtension<StatusColors> {
  const StatusColors({
    required this.pendingPickup,
    required this.inProgress,
    required this.readyForDelivery,
    required this.completed,
  });

  final StatusColorPair pendingPickup;
  final StatusColorPair inProgress;
  final StatusColorPair readyForDelivery;
  final StatusColorPair completed;

  StatusColorPair of(OrderStatus status) => switch (status) {
        OrderStatus.pendingPickup => pendingPickup,
        OrderStatus.inProgress => inProgress,
        OrderStatus.readyForDelivery => readyForDelivery,
        OrderStatus.completed => completed,
      };

  /// The light-theme status palette. `onColor` values are darkened relative to
  /// `color` so 12-pt chip text clears 4.5:1 on the pale tint.
  static const StatusColors light = StatusColors(
    pendingPickup: StatusColorPair(Color(0xFF9A5B00), Color(0xFF6E4000)),
    inProgress: StatusColorPair(Color(0xFF7A4CC2), Color(0xFF5A2EA6)),
    readyForDelivery: StatusColorPair(Color(0xFF0B7285), Color(0xFF075562)),
    completed: StatusColorPair(Color(0xFF2F7D32), Color(0xFF1E5E20)),
  );

  @override
  StatusColors copyWith({
    StatusColorPair? pendingPickup,
    StatusColorPair? inProgress,
    StatusColorPair? readyForDelivery,
    StatusColorPair? completed,
  }) {
    return StatusColors(
      pendingPickup: pendingPickup ?? this.pendingPickup,
      inProgress: inProgress ?? this.inProgress,
      readyForDelivery: readyForDelivery ?? this.readyForDelivery,
      completed: completed ?? this.completed,
    );
  }

  @override
  StatusColors lerp(ThemeExtension<StatusColors>? other, double t) {
    if (other is! StatusColors) return this;
    StatusColorPair lerpPair(StatusColorPair a, StatusColorPair b) =>
        StatusColorPair(
          Color.lerp(a.color, b.color, t)!,
          Color.lerp(a.onColor, b.onColor, t)!,
        );
    return StatusColors(
      pendingPickup: lerpPair(pendingPickup, other.pendingPickup),
      inProgress: lerpPair(inProgress, other.inProgress),
      readyForDelivery: lerpPair(readyForDelivery, other.readyForDelivery),
      completed: lerpPair(completed, other.completed),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/shared/theme/status_colors_test.dart`
Expected: PASS (3 tests). If any contrast assertion fails, darken that status's `onColor` until ≥4.5:1 and re-run.

- [ ] **Step 5: Commit**

```bash
git add lib/src/shared/theme/status_colors.dart test/shared/theme/status_colors_test.dart
git commit -m "feat(theme): add StatusColors theme extension with contrast guard"
```

---

## Task 4: Register StatusColors in the theme, migrate the enum & chip call sites

**Files:**
- Modify: `lib/src/shared/widgets/app_theme.dart` (add `extensions:`)
- Modify: `lib/src/orders/order_status.dart` (remove `color` field)
- Modify: `lib/src/orders/order_details_screen.dart:202,236,436`
- Modify: `lib/src/dashboard/staff_dashboard_screen.dart:977,1046`
- Test: `test/orders/order_status_test.dart` (verify still green)

This is the one behavioral change. After it, no code reads `OrderStatus.color`.

- [ ] **Step 1: Register the extension in the theme**

In `lib/src/shared/widgets/app_theme.dart`, add the import at top:

```dart
import '../theme/status_colors.dart';
```

Inside the `ThemeData(...)` returned by `buildAmuwakTheme()`, add:

```dart
    extensions: const <ThemeExtension<dynamic>>[StatusColors.light],
```

- [ ] **Step 2: Remove `color` from the enum**

Edit `lib/src/orders/order_status.dart`. Replace the enum so values carry only `label`:

```dart
import 'package:flutter/foundation.dart';

@immutable
enum OrderStatus {
  pendingPickup(label: 'Pending pickup'),
  inProgress(label: 'In progress'),
  readyForDelivery(label: 'Ready for delivery'),
  completed(label: 'Completed');

  const OrderStatus({required this.label});

  final String label;

  String toDbString() => switch (this) {
        OrderStatus.pendingPickup => 'pending_pickup',
        OrderStatus.inProgress => 'in_progress',
        OrderStatus.readyForDelivery => 'ready',
        OrderStatus.completed => 'completed',
      };

  OrderStatus? get nextStatus => switch (this) {
        OrderStatus.pendingPickup => OrderStatus.inProgress,
        OrderStatus.inProgress => OrderStatus.readyForDelivery,
        OrderStatus.readyForDelivery => OrderStatus.completed,
        OrderStatus.completed => null,
      };
}
```

(The `material.dart` import is gone; `foundation.dart` provides `@immutable`. If `@immutable` triggers an unused-import lint, drop the annotation and the import.)

- [ ] **Step 3: Run the build to find every broken call site**

Run: `flutter analyze lib/src/orders/order_status.dart lib/src/orders/order_details_screen.dart lib/src/dashboard/staff_dashboard_screen.dart`
Expected: errors at `order_details_screen.dart:202` and `staff_dashboard_screen.dart:977` ("The getter 'color' isn't defined for OrderStatus"). These confirm the only two read sites (matches the spec).

- [ ] **Step 4: Migrate `_StatusChip` to take a resolved pair (both screens)**

The chip is duplicated in both files with identical bodies. Change BOTH to take `color` + `onColor` and render `onColor` for the text.

In `lib/src/orders/order_details_screen.dart` and `lib/src/dashboard/staff_dashboard_screen.dart`, replace the `_StatusChip` class body with:

```dart
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.color, required this.onColor, required this.label});

  final Color color;
  final Color onColor;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs + 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadii.chip),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: onColor,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
```

Add these imports to BOTH files if not present:

```dart
import '../../shared/theme/app_radii.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/theme/status_colors.dart';
```

(`order_details_screen.dart` and `staff_dashboard_screen.dart` are both at `lib/src/<dir>/`, so `../../shared/theme/...` is correct.)

- [ ] **Step 5: Migrate the call sites**

In `lib/src/orders/order_details_screen.dart`, replace line 202:

```dart
    final status = StatusColors.light; // resolved from theme below
```

with a context-based lookup. Since line 202 is inside a `build` with `context`, use:

```dart
    final statusPair = Theme.of(context).extension<StatusColors>()!.of(_order.status);
```

Then at the `_StatusChip(...)` construction (was line 236):

```dart
                          _StatusChip(
                            color: statusPair.color,
                            onColor: statusPair.onColor,
                            label: _order.status.label,
                          ),
```

In `lib/src/dashboard/staff_dashboard_screen.dart`, replace line 977:

```dart
    final statusPair = Theme.of(context).extension<StatusColors>()!.of(order.status);
```

and the chip construction:

```dart
      child: _StatusChip(
        color: statusPair.color,
        onColor: statusPair.onColor,
        label: order.status.label,
      ),
```

- [ ] **Step 6: Run analyze + the status test + both screen tests**

Run each separately (host constraint):

```
flutter analyze lib/src/orders/order_status.dart lib/src/orders/order_details_screen.dart lib/src/dashboard/staff_dashboard_screen.dart
flutter test test/orders/order_status_test.dart
flutter test test/orders/order_details_screen_test.dart
flutter test test/dashboard/staff_dashboard_screen_test.dart
```

Expected: analyze clean; all three test files PASS. If a screen test asserted on `status.color`, update it to assert on the chip's rendered text/`onColor` instead.

- [ ] **Step 7: Commit**

```bash
git add lib/src/orders/order_status.dart lib/src/shared/widgets/app_theme.dart lib/src/orders/order_details_screen.dart lib/src/dashboard/staff_dashboard_screen.dart test/orders/order_status_test.dart
git commit -m "refactor(theme): move order-status colors into StatusColors extension"
```

---

## Task 5: AppCard widget + CardTheme

**Files:**
- Create: `lib/src/shared/theme/app_card.dart`
- Test: `test/shared/theme/app_card_test.dart`

`AppCard` is a thin wrapper over Material `Card`, giving the repeated white-container pattern (radius `AppRadii.card`, `AppColors.cardBorder` hairline, `AppSpacing.lg` padding) one definition. Swapping the ~20 `BoxDecoration` sites happens during the screen sweep (Task 7), not here.

- [ ] **Step 1: Write the failing test**

Create `test/shared/theme/app_card_test.dart`:

```dart
import 'package:amuwak_staff/src/shared/theme/app_card.dart';
import 'package:amuwak_staff/src/shared/theme/app_radii.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AppCard renders its child inside a Card with the card radius',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AppCard(child: Text('hello'))),
      ),
    );

    expect(find.text('hello'), findsOneWidget);
    final card = tester.widget<Card>(find.byType(Card));
    final shape = card.shape as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.circular(AppRadii.card));
  });

  testWidgets('AppCard onTap makes it tappable', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppCard(onTap: () => tapped = true, child: const Text('tap')),
        ),
      ),
    );
    await tester.tap(find.text('tap'));
    expect(tapped, isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/shared/theme/app_card_test.dart`
Expected: FAIL — `app_card.dart` URI doesn't exist.

- [ ] **Step 3: Write minimal implementation**

Create `lib/src/shared/theme/app_card.dart`:

```dart
import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_radii.dart';
import 'app_spacing.dart';

/// The app's standard white container: rounded, hairline-bordered, padded.
/// Replaces the repeated inline `BoxDecoration` card pattern. Optionally
/// tappable via [onTap].
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadii.card),
      side: const BorderSide(color: AppColors.cardBorder),
    );
    return Card(
      elevation: 0,
      color: AppColors.white,
      margin: EdgeInsets.zero,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/shared/theme/app_card_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/src/shared/theme/app_card.dart test/shared/theme/app_card_test.dart
git commit -m "feat(theme): add AppCard widget for the shared card pattern"
```

---

## Task 6: Rewrite app_theme.dart — trimmed scheme, full TextTheme, CardTheme

**Files:**
- Modify: `lib/src/shared/widgets/app_theme.dart`
- Test: `test/shared/widgets/app_theme_test.dart`

Rewrites the assembler to consume `AppColors`/`AppRadii`, trim the redundant `fromSeed` overrides, complete the `TextTheme` ramp, and add `CardThemeData`. Keeps `buildAmuwakTheme()` signature so `main.dart` is untouched.

- [ ] **Step 1: Write the failing test**

Create `test/shared/widgets/app_theme_test.dart`:

```dart
import 'package:amuwak_staff/src/shared/theme/app_colors.dart';
import 'package:amuwak_staff/src/shared/theme/app_radii.dart';
import 'package:amuwak_staff/src/shared/theme/status_colors.dart';
import 'package:amuwak_staff/src/shared/widgets/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final theme = buildAmuwakTheme();

  test('uses Material 3 and the brand primary', () {
    expect(theme.useMaterial3, isTrue);
    expect(theme.colorScheme.primary, AppColors.primary);
  });

  test('secondary is no longer pinned equal to primary', () {
    // The old theme set secondary == primary; the trimmed scheme lets the
    // algorithm derive a distinct secondary.
    expect(theme.colorScheme.secondary, isNot(AppColors.primary));
  });

  test('registers the StatusColors extension', () {
    expect(theme.extension<StatusColors>(), isNotNull);
  });

  test('completes the text ramp used by screens', () {
    expect(theme.textTheme.titleLarge, isNotNull);
    expect(theme.textTheme.headlineMedium, isNotNull);
    expect(theme.textTheme.bodySmall, isNotNull);
  });

  test('card theme uses the card radius', () {
    final shape = theme.cardTheme.shape as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.circular(AppRadii.card));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/shared/widgets/app_theme_test.dart`
Expected: FAIL — `secondary` still equals primary and/or `cardTheme.shape` is null.

- [ ] **Step 3: Rewrite the implementation**

Replace the full contents of `lib/src/shared/widgets/app_theme.dart`:

```dart
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radii.dart';
import '../theme/status_colors.dart';

ThemeData buildAmuwakTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    // Brand-critical overrides only. Let the algorithm derive secondary,
    // surface, and onSurface so the palette stays harmonious.
    primary: AppColors.primary,
    onPrimary: AppColors.dark,
    primaryContainer: AppColors.surfaceBrand,
    onPrimaryContainer: AppColors.white,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: AppColors.background,
    extensions: const <ThemeExtension<dynamic>>[StatusColors.light],
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surfaceBrand,
      foregroundColor: AppColors.white,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.white,
      indicatorColor: AppColors.primary.withValues(alpha: 0.16),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          color: selected ? AppColors.primary : AppColors.secondaryText,
          size: 24,
        );
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          color: selected ? AppColors.dark : AppColors.secondaryText,
          fontSize: 12,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
        );
      }),
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(color: AppColors.dark, fontWeight: FontWeight.bold),
      headlineMedium: TextStyle(color: AppColors.dark, fontWeight: FontWeight.bold),
      titleLarge: TextStyle(
          color: AppColors.dark, fontSize: 21, fontWeight: FontWeight.bold),
      titleMedium: TextStyle(
          color: AppColors.dark, fontSize: 16, fontWeight: FontWeight.w700),
      bodyMedium: TextStyle(color: AppColors.dark),
      bodySmall: TextStyle(color: AppColors.secondaryText, fontSize: 13),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: AppColors.white,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.card),
        side: const BorderSide(color: AppColors.cardBorder),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.dark,
        minimumSize: const Size(double.infinity, 54),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.field)),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.primary,
      foregroundColor: AppColors.dark,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.white,
      prefixIconColor: AppColors.primary,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.field),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.field),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
    ),
  );
}
```

- [ ] **Step 4: Handle the old brand constants**

Other files still import `amuwakPrimary`, `amuwakDark`, etc. from `app_theme.dart`. They are removed above. To keep the build green until the screen sweep (Task 7), add backward-compat aliases at the bottom of `app_theme.dart`:

```dart
// Deprecated brand-constant aliases. Removed as screens migrate to AppColors.
const Color amuwakPrimary = AppColors.primary;
const Color amuwakSurfaceBrand = AppColors.surfaceBrand;
const Color amuwakDark = AppColors.dark;
const Color amuwakBackground = AppColors.background;
const Color amuwakWhite = AppColors.white;
```

- [ ] **Step 5: Run the theme test + analyze the app**

```
flutter test test/shared/widgets/app_theme_test.dart
flutter analyze lib
```

Expected: theme test PASS (5 tests); `flutter analyze lib` clean (aliases keep screens compiling).

- [ ] **Step 6: Run the full widget-test suite per file to catch visual-role regressions**

The trimmed scheme changes generated `surface`/`secondary`. Run the existing screen tests (one file each) to confirm nothing asserts on the old generated values:

```
flutter test test/dashboard/staff_dashboard_screen_test.dart
flutter test test/orders/order_details_screen_test.dart
flutter test test/reports/daily_report_screen_test.dart
flutter test test/auth/login_screen_test.dart
flutter test test/sync/sync_status_banner_test.dart
```

Expected: all PASS. Fix any test asserting on a now-changed generated color by pointing it at the role (`colorScheme.secondary`) rather than a literal.

- [ ] **Step 7: Commit**

```bash
git add lib/src/shared/widgets/app_theme.dart test/shared/widgets/app_theme_test.dart
git commit -m "refactor(theme): assemble theme from tokens; trim scheme; add CardTheme + text ramp"
```

---

## Task 7: Screen sweep — replace inline colors/sizes with roles & tokens

Mechanical, one screen per commit. For EACH screen below: replace hardcoded values per the mapping table, swap the white-container `BoxDecoration` pattern for `AppCard`, run that screen's test file, then commit. Keep behavior identical — this is a styling swap, not a redesign.

**Replacement mapping (apply consistently):**

| Found | Replace with |
|-------|--------------|
| `amuwakWhite` (as surface) | `AppColors.white` (or rely on `AppCard`/`cardTheme`) |
| `amuwakBackground` | `Theme.of(context).scaffoldBackgroundColor` |
| `amuwakPrimary` | `Theme.of(context).colorScheme.primary` (or `AppColors.primary` in const contexts) |
| `amuwakDark` body text | `Theme.of(context).colorScheme.onSurface` |
| `Colors.black54` / `Colors.white70` (secondary text) | `AppColors.secondaryText` / `Theme.of(context).textTheme.bodySmall?.color` |
| `Colors.white` text on terracotta header | `AppColors.white` (full opacity — fixes the white70 contrast bug) |
| `Colors.red`/`Colors.red.shade*` (errors) | `Theme.of(context).colorScheme.error` |
| `TextStyle(fontSize: 21, fontWeight: bold)` section header | `Theme.of(context).textTheme.titleLarge` |
| `TextStyle(fontSize: 16, w700)` | `textTheme.titleMedium` |
| caption `TextStyle(fontSize: 12/13, black54)` | `textTheme.bodySmall` |
| `BorderRadius.circular(14..24)` | nearest `AppRadii.field`/`card`/`chip` |
| `EdgeInsets.all(16)` etc. | `EdgeInsets.all(AppSpacing.lg)` etc. |
| `SizedBox(height: 8/12/16/...)` | `SizedBox(height: AppSpacing.sm/md/lg/...)` |
| white-container `DecoratedBox`/`Container` w/ `BoxDecoration` + primary-18% border | `AppCard(child: ...)` |

Add to each migrated screen as needed:
```dart
import '../../shared/theme/app_card.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_radii.dart';
import '../../shared/theme/app_spacing.dart';
```
(adjust `../` depth: screens at `lib/src/<dir>/` use `../../shared/theme/...`; `lib/src/orders/proof/` uses `../../../shared/theme/...`.)

---

### Task 7a: staff_dashboard_screen.dart

**Files:**
- Modify: `lib/src/dashboard/staff_dashboard_screen.dart`
- Test: `test/dashboard/staff_dashboard_screen_test.dart`

- [ ] **Step 1:** Apply the mapping table across the file. Convert `_OrderCard`'s `DecoratedBox(decoration: BoxDecoration(color: amuwakWhite, borderRadius: circular(24), border: ...))` + inner `Material`/`InkWell`/`Padding` into:

```dart
    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [ /* existing children unchanged */ ],
      ),
    );
```

Replace `_SummaryCard`/`_ActionButton`/section containers' white `BoxDecoration`s with `AppCard` likewise. Replace `Colors.black54` → `AppColors.secondaryText`, header `Colors.white`/`white70` → `AppColors.white`, `fontSize:` section headers → `textTheme` roles, magic spacing → `AppSpacing`.

- [ ] **Step 2:** Run: `flutter analyze lib/src/dashboard/staff_dashboard_screen.dart` → clean.
- [ ] **Step 3:** Run: `flutter test test/dashboard/staff_dashboard_screen_test.dart` → PASS. Adjust any test that found a widget by an old literal color.
- [ ] **Step 4:** Commit:

```bash
git add lib/src/dashboard/staff_dashboard_screen.dart test/dashboard/staff_dashboard_screen_test.dart
git commit -m "refactor(theme): route dashboard styling through theme roles and AppCard"
```

---

### Task 7b: order_details_screen.dart

**Files:**
- Modify: `lib/src/orders/order_details_screen.dart`
- Test: `test/orders/order_details_screen_test.dart`

- [ ] **Step 1:** Apply the mapping table. Convert the detail-block `BoxDecoration` containers (incl. the one near :199) to `AppCard`. Header sub-labels using `Colors.white70` → `AppColors.white`. `_DetailRow` label/value `fontSize:` → `textTheme` roles.
- [ ] **Step 2:** Run: `flutter analyze lib/src/orders/order_details_screen.dart` → clean.
- [ ] **Step 3:** Run: `flutter test test/orders/order_details_screen_test.dart` → PASS.
- [ ] **Step 4:** Commit:

```bash
git add lib/src/orders/order_details_screen.dart test/orders/order_details_screen_test.dart
git commit -m "refactor(theme): route order-details styling through theme roles and AppCard"
```

---

### Task 7c: daily_report_screen.dart

**Files:**
- Modify: `lib/src/reports/daily_report_screen.dart`
- Test: `test/reports/daily_report_screen_test.dart`

- [ ] **Step 1:** Apply the mapping table; convert the 5 `BoxDecoration` summary/progress cards to `AppCard`; reconcile the 42/46px icon tiles to a single `AppSpacing`-based size; `fontSize:` metric numbers → `textTheme.headlineMedium`.
- [ ] **Step 2:** Run: `flutter analyze lib/src/reports/daily_report_screen.dart` → clean.
- [ ] **Step 3:** Run: `flutter test test/reports/daily_report_screen_test.dart` → PASS.
- [ ] **Step 4:** Commit:

```bash
git add lib/src/reports/daily_report_screen.dart test/reports/daily_report_screen_test.dart
git commit -m "refactor(theme): route daily-report styling through theme roles and AppCard"
```

---

### Task 7d: login_screen.dart

**Files:**
- Modify: `lib/src/auth/login_screen.dart`
- Test: `test/auth/login_screen_test.dart`

- [ ] **Step 1:** Apply the mapping table. `amuwakDark` title → `textTheme.headlineMedium`; `Colors.black54` subtitle → `AppColors.secondaryText`; error `Colors.red`/`red.shade50` → `colorScheme.error`/`colorScheme.errorContainer`.
- [ ] **Step 2:** Run: `flutter analyze lib/src/auth/login_screen.dart` → clean.
- [ ] **Step 3:** Run: `flutter test test/auth/login_screen_test.dart` → PASS.
- [ ] **Step 4:** Commit:

```bash
git add lib/src/auth/login_screen.dart test/auth/login_screen_test.dart
git commit -m "refactor(theme): route login styling through theme roles"
```

---

### Task 7e: capture screens (pickup + delivery)

**Files:**
- Modify: `lib/src/orders/proof/pickup_capture_screen.dart`
- Modify: `lib/src/orders/proof/delivery_capture_screen.dart`
- Test: `test/orders/proof/pickup_capture_screen_test.dart`, `test/orders/proof/delivery_capture_screen_test.dart`

- [ ] **Step 1:** Apply the mapping table to BOTH; convert their white-container `BoxDecoration`s to `AppCard`. Note the `../../../shared/theme/` import depth here.
- [ ] **Step 2:** Run: `flutter analyze lib/src/orders/proof/pickup_capture_screen.dart lib/src/orders/proof/delivery_capture_screen.dart` → clean.
- [ ] **Step 3:** Run each test file separately:

```
flutter test test/orders/proof/pickup_capture_screen_test.dart
flutter test test/orders/proof/delivery_capture_screen_test.dart
```

Expected: PASS.
- [ ] **Step 4:** Commit:

```bash
git add lib/src/orders/proof/pickup_capture_screen.dart lib/src/orders/proof/delivery_capture_screen.dart
git commit -m "refactor(theme): route capture-screen styling through theme roles and AppCard"
```

---

### Task 7f: sync_status_banner.dart — banner colors via theme

**Files:**
- Modify: `lib/src/shared/widgets/sync_status_banner.dart`
- Test: `test/sync/sync_status_banner_test.dart`

The banner hardcodes `Colors.red/orange/blue.shade100/900`. Route error → `colorScheme.error`/`errorContainer`; keep offline (orange) and pending (blue) as named constants in `AppColors` so they're centralized. The banner test asserts on copy/visibility, not specific shades — confirm it still passes.

- [ ] **Step 1:** Add to `AppColors` (extend Task 2's file):

```dart
  // Sync-banner state colors (centralized; not part of the M3 scheme).
  static const Color offlineBg = Color(0xFFFFE0B2); // orange 100
  static const Color offlineFg = Color(0xFFE65100); // orange 900
  static const Color pendingBg = Color(0xFFBBDEFB); // blue 100
  static const Color pendingFg = Color(0xFF0D47A1); // blue 900
```

- [ ] **Step 2:** In `sync_status_banner.dart`, replace error `Colors.red.shade900`/`shade100` with `Theme.of(context).colorScheme.onErrorContainer`/`errorContainer`; replace offline/pending shades with the `AppColors` constants above. Add `import '../theme/app_colors.dart';`.
- [ ] **Step 3:** Run: `flutter analyze lib/src/shared/widgets/sync_status_banner.dart` → clean.
- [ ] **Step 4:** Run: `flutter test test/sync/sync_status_banner_test.dart` → PASS.
- [ ] **Step 5:** Commit:

```bash
git add lib/src/shared/widgets/sync_status_banner.dart lib/src/shared/theme/app_colors.dart test/sync/sync_status_banner_test.dart
git commit -m "refactor(theme): route sync banner colors through theme and AppColors"
```

---

## Task 8: Remove the deprecated brand-constant aliases

**Files:**
- Modify: `lib/src/shared/widgets/app_theme.dart`

After the sweep, no screen should reference `amuwakPrimary` etc.

- [ ] **Step 1:** Run: `flutter analyze lib` and grep for remaining uses:

```
git grep -n "amuwakPrimary\|amuwakDark\|amuwakWhite\|amuwakBackground\|amuwakSurfaceBrand" lib
```

Expected: matches only inside `lib/src/shared/widgets/app_theme.dart` (the alias block). If other files still match, migrate them (apply the Task 7 mapping) before continuing.

- [ ] **Step 2:** Delete the deprecated alias block from `app_theme.dart` (the five `const Color amuwak... = AppColors....;` lines).
- [ ] **Step 3:** Run: `flutter analyze lib` → clean (no undefined-name errors).
- [ ] **Step 4:** Run the full test suite, one file at a time, to confirm green. At minimum re-run the screen test files touched in Task 7 plus the theme tests.
- [ ] **Step 5:** Commit:

```bash
git add lib/src/shared/widgets/app_theme.dart
git commit -m "refactor(theme): drop deprecated brand-constant aliases"
```

---

## Self-Review Notes (for the implementer)

- **Spec coverage:** color/text roles (Tasks 6–7), spacing/radius tokens (Task 1, applied in 7), AppCard/CardTheme (Tasks 5–6, applied in 7), StatusColors extension + contrast fix (Tasks 3–4), trimmed `fromSeed` (Task 6). All spec sections map to tasks.
- **Type consistency:** `StatusColors.of()` returns `StatusColorPair {color, onColor}`; `_StatusChip` takes `color`+`onColor`+`label` in both screens; `AppCard({child, onTap, padding})` used consistently in Task 7.
- **CardThemeData vs CardTheme:** Flutter 3.35 `ThemeData.cardTheme` expects `CardThemeData` (used in Task 6). If a future SDK bump warns, follow the deprecation.
- **Per-file testing:** every code task runs exactly one test file per command, per the Windows-host constraint.
```
