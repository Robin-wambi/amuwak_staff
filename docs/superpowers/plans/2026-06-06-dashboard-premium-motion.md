# Dashboard Premium Motion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add restrained, premium motion to the staff dashboard — staggered entrance reveals, count-up stat numbers, a subtle animated gradient header, and an app-wide press-scale — using native Flutter with zero new dependencies.

**Architecture:** A new `AppMotion` token class (sibling to `AppSpacing`/`AppElevation`/`AppRadii`) centralizes all durations, curves, and offsets. Four independent, reusable widgets live under `lib/src/shared/motion/`. The dashboard wires them in; `AppCard` gains the press-scale so it applies app-wide. Every widget honours the OS "reduce motion" setting via `MediaQuery.disableAnimations`.

**Tech Stack:** Flutter (Material 3), `flutter_test` for widget tests. No new packages.

**Spec:** `docs/superpowers/specs/2026-06-06-dashboard-premium-motion-design.md`

**Testing note (this host):** Per project convention, run `flutter test` **one file at a time** — multi-file invocations hang at loading on this Windows host. Each test step below names a single file.

**Key cross-cutting facts (read once):**
- Reduce-motion is read with `MediaQuery.of(context).disableAnimations`.
- The animated gradient repeats **forever**, so any test that pumps a screen containing it must use `pump()` (not `pumpAndSettle()`), OR enable reduce-motion. The dashboard test helper is updated to enable reduce-motion (Task 7) so existing `pumpAndSettle()` tests keep working.
- In tests, enable reduce-motion with:
  ```dart
  Builder(builder: (c) => MediaQuery(
    data: MediaQuery.of(c).copyWith(disableAnimations: true),
    child: /* widget under test */,
  ))
  ```

---

## File Structure

**New files:**
- `lib/src/shared/theme/app_motion.dart` — motion tokens (durations, curves, offsets).
- `lib/src/shared/motion/pressable_scale.dart` — press-scale wrapper.
- `lib/src/shared/motion/reveal_on_mount.dart` — staggered fade+slide entrance.
- `lib/src/shared/motion/count_up_text.dart` — number that counts up to its value.
- `lib/src/shared/motion/animated_gradient_header.dart` — subtle living gradient surface.
- `test/shared/motion/pressable_scale_test.dart`
- `test/shared/motion/reveal_on_mount_test.dart`
- `test/shared/motion/count_up_text_test.dart`
- `test/shared/motion/animated_gradient_header_test.dart`

**Modified files:**
- `lib/src/shared/theme/app_card.dart` — wrap tappable path in `PressableScale`.
- `lib/src/dashboard/staff_dashboard_screen.dart` — wire reveals, count-up, gradient header; `_SummaryCard.value` becomes `int`.
- `test/dashboard/staff_dashboard_screen_test.dart` — enable reduce-motion in the pump helper; add a content-after-settle test.

---

## Task 1: Motion tokens (`AppMotion`)

**Files:**
- Create: `lib/src/shared/theme/app_motion.dart`

- [ ] **Step 1: Create the tokens file**

```dart
import 'package:flutter/material.dart';

/// Motion scale — the app's single source for animation timing and shaping.
///
/// Sibling to [AppSpacing], [AppElevation], [AppRadii]. Values are kept
/// conservative (sourced from the Material 3 motion spec) because this is a
/// field operations tool: motion must add polish without competing with
/// content or hurting performance.
abstract final class AppMotion {
  /// Press feedback (scale down/up).
  static const Duration fast = Duration(milliseconds: 150);

  /// A single entrance reveal.
  static const Duration medium = Duration(milliseconds: 320);

  /// Count-up total duration.
  static const Duration slow = Duration(milliseconds: 600);

  /// One full cycle of the header gradient sheen.
  static const Duration gradientLoop = Duration(seconds: 6);

  /// Delay between successive sibling reveals.
  static const Duration stagger = Duration(milliseconds: 80);

  /// Standard easing for reveals and press.
  static const Curve standard = Curves.easeOutCubic;

  /// Easing for the gradient lerp.
  static const Curve emphasized = Curves.easeInOut;

  /// Upward slide distance for an entrance reveal (logical px).
  static const double revealOffset = 16;

  /// Scale factor applied while a surface is pressed.
  static const double pressScale = 0.97;
}
```

- [ ] **Step 2: Verify it analyses clean**

Run: `flutter analyze lib/src/shared/theme/app_motion.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/src/shared/theme/app_motion.dart
git commit -m "feat(motion): add AppMotion timing and shaping tokens"
```

---

## Task 2: `PressableScale` widget

**Files:**
- Create: `lib/src/shared/motion/pressable_scale.dart`
- Test: `test/shared/motion/pressable_scale_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_staff/src/shared/motion/pressable_scale.dart';

void main() {
  testWidgets('forwards tap to onTap', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PressableScale(
            onTap: () => tapped = true,
            child: const SizedBox(width: 100, height: 100),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(PressableScale));
    await tester.pumpAndSettle();
    expect(tapped, isTrue);
  });

  testWidgets('scales down while pressed and returns to 1 after release',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PressableScale(
            onTap: () {},
            child: const SizedBox(width: 100, height: 100),
          ),
        ),
      ),
    );

    AnimatedScale scaleWidget() =>
        tester.widget<AnimatedScale>(find.byType(AnimatedScale));
    expect(scaleWidget().scale, 1.0);

    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(PressableScale)));
    await tester.pump(); // dispatch tap-down
    expect(scaleWidget().scale, lessThan(1.0));

    await gesture.up();
    await tester.pumpAndSettle();
    expect(scaleWidget().scale, 1.0);
  });

  testWidgets('reduced motion keeps the scale at 1 while pressed',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) => MediaQuery(
            data: MediaQuery.of(c).copyWith(disableAnimations: true),
            child: Scaffold(
              body: PressableScale(
                onTap: () {},
                child: const SizedBox(width: 100, height: 100),
              ),
            ),
          ),
        ),
      ),
    );

    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(PressableScale)));
    await tester.pump();
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1.0);
    await gesture.up();
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/shared/motion/pressable_scale_test.dart`
Expected: FAIL — `Target of URI doesn't exist: '.../pressable_scale.dart'`.

- [ ] **Step 3: Write the implementation**

```dart
import 'package:flutter/material.dart';

import '../theme/app_motion.dart';

/// Wraps a [child] so it scales down slightly while pressed, springing back
/// on release — a tactile, premium press feedback. Owns the tap via a
/// [GestureDetector] (so it behaves correctly inside scrollables: a scroll
/// that wins the gesture arena fires `onTapCancel` and the scale releases).
///
/// Honours the OS reduce-motion setting: when disabled, the scale stays at 1.
class PressableScale extends StatefulWidget {
  const PressableScale({super.key, required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (mounted && _pressed != value) {
      setState(() => _pressed = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final scaled = AnimatedScale(
      scale: (_pressed && !reduceMotion) ? AppMotion.pressScale : 1.0,
      duration: reduceMotion ? Duration.zero : AppMotion.fast,
      curve: AppMotion.standard,
      child: widget.child,
    );

    if (widget.onTap == null) return scaled;

    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        child: scaled,
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/shared/motion/pressable_scale_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/src/shared/motion/pressable_scale.dart test/shared/motion/pressable_scale_test.dart
git commit -m "feat(motion): add PressableScale press-feedback widget"
```

---

## Task 3: `RevealOnMount` widget

**Files:**
- Create: `lib/src/shared/motion/reveal_on_mount.dart`
- Test: `test/shared/motion/reveal_on_mount_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_staff/src/shared/motion/reveal_on_mount.dart';

void main() {
  testWidgets('child is fully opaque after the reveal settles',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: RevealOnMount(child: Text('hello'))),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('hello'), findsOneWidget);
    final opacity = tester.widget<Opacity>(
      find.ancestor(of: find.text('hello'), matching: find.byType(Opacity)),
    );
    expect(opacity.opacity, 1.0);
  });

  testWidgets('honours the delay before revealing', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RevealOnMount(
            delay: Duration(milliseconds: 200),
            child: Text('delayed'),
          ),
        ),
      ),
    );

    // Immediately after mount, before the delay elapses, it is not yet visible.
    await tester.pump();
    final opacity = tester.widget<Opacity>(
      find.ancestor(of: find.text('delayed'), matching: find.byType(Opacity)),
    );
    expect(opacity.opacity, 0.0);

    await tester.pumpAndSettle();
    final settled = tester.widget<Opacity>(
      find.ancestor(of: find.text('delayed'), matching: find.byType(Opacity)),
    );
    expect(settled.opacity, 1.0);
  });

  testWidgets('reduced motion shows the child immediately (no Opacity wrapper)',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) => MediaQuery(
            data: MediaQuery.of(c).copyWith(disableAnimations: true),
            child: const Scaffold(body: RevealOnMount(child: Text('instant'))),
          ),
        ),
      ),
    );

    await tester.pump();
    expect(find.text('instant'), findsOneWidget);
    expect(
      find.ancestor(of: find.text('instant'), matching: find.byType(Opacity)),
      findsNothing,
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/shared/motion/reveal_on_mount_test.dart`
Expected: FAIL — URI does not exist.

- [ ] **Step 3: Write the implementation**

```dart
import 'package:flutter/material.dart';

import '../theme/app_motion.dart';

/// Fades a [child] in (0→1) and slides it up ([AppMotion.revealOffset]→0) once,
/// when it first mounts. Pass [delay] to stagger siblings:
/// `RevealOnMount(delay: AppMotion.stagger * index, child: ...)`.
///
/// Honours reduce-motion: the child appears immediately with no animation and
/// no pending timer.
class RevealOnMount extends StatefulWidget {
  const RevealOnMount({
    super.key,
    required this.child,
    this.delay = Duration.zero,
  });

  final Widget child;
  final Duration delay;

  @override
  State<RevealOnMount> createState() => _RevealOnMountState();
}

class _RevealOnMountState extends State<RevealOnMount>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.medium,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;

    // Reduce-motion: jump straight to the final frame, schedule no timer.
    if (MediaQuery.of(context).disableAnimations) {
      _controller.value = 1.0;
      return;
    }
    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      Future<void>.delayed(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // When motion is disabled, render the child directly — no Opacity/Transform.
    if (MediaQuery.of(context).disableAnimations) {
      return widget.child;
    }

    final curved = CurvedAnimation(
      parent: _controller,
      curve: AppMotion.standard,
    );
    return AnimatedBuilder(
      animation: curved,
      builder: (context, child) {
        return Opacity(
          opacity: curved.value,
          child: Transform.translate(
            offset: Offset(0, AppMotion.revealOffset * (1 - curved.value)),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/shared/motion/reveal_on_mount_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/src/shared/motion/reveal_on_mount.dart test/shared/motion/reveal_on_mount_test.dart
git commit -m "feat(motion): add RevealOnMount staggered entrance widget"
```

---

## Task 4: `CountUpText` widget

**Files:**
- Create: `lib/src/shared/motion/count_up_text.dart`
- Test: `test/shared/motion/count_up_text_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_staff/src/shared/motion/count_up_text.dart';

void main() {
  testWidgets('counts up to the target value after settle', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: CountUpText(value: 7))),
    );

    await tester.pumpAndSettle();
    expect(find.text('7'), findsOneWidget);
  });

  testWidgets('reduced motion shows the final value immediately',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) => MediaQuery(
            data: MediaQuery.of(c).copyWith(disableAnimations: true),
            child: const Scaffold(body: CountUpText(value: 42)),
          ),
        ),
      ),
    );

    await tester.pump();
    expect(find.text('42'), findsOneWidget);
  });

  testWidgets('animates to a new value when it changes', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: CountUpText(value: 3))),
    );
    await tester.pumpAndSettle();
    expect(find.text('3'), findsOneWidget);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: CountUpText(value: 9))),
    );
    await tester.pumpAndSettle();
    expect(find.text('9'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/shared/motion/count_up_text_test.dart`
Expected: FAIL — URI does not exist.

- [ ] **Step 3: Write the implementation**

```dart
import 'package:flutter/material.dart';

import '../theme/app_motion.dart';

/// Renders an integer [value] that animates up to its target. When [value]
/// changes the tween re-runs from the currently displayed number to the new
/// one (implicit-animation behaviour). Honours reduce-motion (jumps to value).
class CountUpText extends StatelessWidget {
  const CountUpText({super.key, required this.value, this.style});

  final int value;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final duration = MediaQuery.of(context).disableAnimations
        ? Duration.zero
        : AppMotion.slow;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value.toDouble()),
      duration: duration,
      curve: AppMotion.standard,
      builder: (context, animatedValue, _) {
        return Text(animatedValue.round().toString(), style: style);
      },
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/shared/motion/count_up_text_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/src/shared/motion/count_up_text.dart test/shared/motion/count_up_text_test.dart
git commit -m "feat(motion): add CountUpText counting-number widget"
```

---

## Task 5: `AnimatedGradientHeader` widget

**Files:**
- Create: `lib/src/shared/motion/animated_gradient_header.dart`
- Test: `test/shared/motion/animated_gradient_header_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_staff/src/shared/motion/animated_gradient_header.dart';

void main() {
  testWidgets('renders its child', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AnimatedGradientHeader(child: Text('header'))),
      ),
    );

    // The sheen repeats forever — pump a frame, do NOT pumpAndSettle.
    await tester.pump();
    expect(find.text('header'), findsOneWidget);

    // The gradient paints onto a Container decoration.
    final container = tester.widget<Container>(
      find.ancestor(of: find.text('header'), matching: find.byType(Container)),
    );
    final decoration = container.decoration as BoxDecoration;
    expect(decoration.gradient, isA<LinearGradient>());
  });

  testWidgets('reduced motion settles (no repeating ticker) and shows child',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) => MediaQuery(
            data: MediaQuery.of(c).copyWith(disableAnimations: true),
            child: const Scaffold(
              body: AnimatedGradientHeader(child: Text('static')),
            ),
          ),
        ),
      ),
    );

    // If the controller were repeating, this would time out.
    await tester.pumpAndSettle();
    expect(find.text('static'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/shared/motion/animated_gradient_header_test.dart`
Expected: FAIL — URI does not exist.

- [ ] **Step 3: Write the implementation**

```dart
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_motion.dart';
import '../theme/app_radii.dart';

/// A brand-coloured header surface with a slow, very subtle gradient sheen that
/// travels diagonally — making the surface feel "alive" without drawing the eye
/// away from content. Drop-in replacement for the dashboard's flat brand header
/// container: keeps the card radius and the soft brand shadow.
///
/// Honours reduce-motion: paints a single static gradient frame.
class AnimatedGradientHeader extends StatefulWidget {
  const AnimatedGradientHeader({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  State<AnimatedGradientHeader> createState() => _AnimatedGradientHeaderState();
}

class _AnimatedGradientHeaderState extends State<AnimatedGradientHeader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.gradientLoop,
  );
  bool _started = false;

  // The sheen travels between the brand terracotta and a slightly lighter
  // terracotta — low contrast, so it reads as a living surface, not a flashy
  // gradient.
  static final Color _base = AppColors.surfaceBrand;
  static final Color _light =
      Color.lerp(AppColors.surfaceBrand, AppColors.white, 0.10)!;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!MediaQuery.of(context).disableAnimations) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadii.card);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = AppMotion.emphasized.transform(_controller.value);
        final begin = Color.lerp(_base, _light, t)!;
        final end = Color.lerp(_light, _base, t)!;
        return Container(
          padding: widget.padding,
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [begin, end],
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.surfaceBrand.withValues(alpha: 0.18),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/shared/motion/animated_gradient_header_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/src/shared/motion/animated_gradient_header.dart test/shared/motion/animated_gradient_header_test.dart
git commit -m "feat(motion): add AnimatedGradientHeader living-surface widget"
```

---

## Task 6: App-wide press-scale on `AppCard`

**Files:**
- Modify: `lib/src/shared/theme/app_card.dart`
- Existing test (must stay green): `test/shared/theme/app_card_test.dart`

**Context:** Today `AppCard` wraps its tappable path in an `InkWell`. We replace that with `PressableScale` so the whole card (shadow + border + content) scales on press, app-wide. The existing `app_card_test.dart` only asserts (a) *no* InkWell when non-tappable, (b) tap fires `onTap`, (c) the resting shadow is present — all preserved. The ripple is intentionally replaced by the scale.

- [ ] **Step 1: Update the failing-first expectation by editing the existing test**

Add this test to `test/shared/theme/app_card_test.dart` inside `main()` (it fails until the implementation changes):

```dart
  testWidgets('tappable AppCard scales via PressableScale', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppCard(onTap: () {}, child: const Text('press')),
        ),
      ),
    );

    expect(find.byType(PressableScale), findsOneWidget);
  });
```

Add this import at the top of the same test file:

```dart
import 'package:amuwak_staff/src/shared/motion/pressable_scale.dart';
```

- [ ] **Step 2: Run test to verify the new case fails**

Run: `flutter test test/shared/theme/app_card_test.dart`
Expected: the new `tappable AppCard scales via PressableScale` test FAILS (`findsNothing`); the others pass.

- [ ] **Step 3: Update `app_card.dart`**

Replace the `build` method body in `lib/src/shared/theme/app_card.dart` with:

```dart
  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadii.card),
      side: const BorderSide(color: AppColors.cardBorder),
    );
    final padded = Padding(padding: padding, child: child);
    // The soft resting shadow lives on an outer DecoratedBox (the elevation:0
    // Card paints no shadow itself); its radius matches the card so the shadow
    // follows the rounded corners.
    final card = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.card),
        boxShadow: AppElevation.resting,
      ),
      child: Card(
        elevation: 0,
        color: AppColors.white,
        margin: EdgeInsets.zero,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: padded,
      ),
    );
    // Only attach press behaviour when the card is actually tappable;
    // PressableScale both forwards the tap and scales the whole card.
    return onTap == null ? card : PressableScale(onTap: onTap, child: card);
  }
```

Add this import near the other imports in `lib/src/shared/theme/app_card.dart`:

```dart
import '../motion/pressable_scale.dart';
```

- [ ] **Step 4: Run the AppCard test to verify all pass**

Run: `flutter test test/shared/theme/app_card_test.dart`
Expected: PASS (all tests, including the new PressableScale case and the existing shadow/tap/no-InkWell cases).

- [ ] **Step 5: Commit**

```bash
git add lib/src/shared/theme/app_card.dart test/shared/theme/app_card_test.dart
git commit -m "feat(motion): scale AppCard on press app-wide via PressableScale"
```

---

## Task 7: Wire motion into the dashboard

**Files:**
- Modify: `lib/src/dashboard/staff_dashboard_screen.dart`
- Modify: `test/dashboard/staff_dashboard_screen_test.dart`

**Context:** Three wirings — (1) `_DashboardHeader` uses `AnimatedGradientHeader`; (2) `_SummaryCard.value` becomes an `int` rendered via `CountUpText`; (3) `_DashboardBody` wraps content blocks in staggered `RevealOnMount`. Because the gradient repeats forever, the test pump helper is updated to enable reduce-motion so existing `pumpAndSettle()` tests keep working.

- [ ] **Step 1: Add motion imports to the dashboard**

In `lib/src/dashboard/staff_dashboard_screen.dart`, add near the other `../shared/...` imports:

```dart
import '../shared/motion/animated_gradient_header.dart';
import '../shared/motion/count_up_text.dart';
import '../shared/motion/reveal_on_mount.dart';
import '../shared/theme/app_motion.dart';
```

- [ ] **Step 2: Swap the header background for `AnimatedGradientHeader`**

In `_DashboardHeader.build`, replace the outer `Container(...)` (the one with `decoration: BoxDecoration(color: AppColors.surfaceBrand, ...)`) with `AnimatedGradientHeader`, keeping the exact same `Row` child. The method becomes:

```dart
  @override
  Widget build(BuildContext context) {
    return AnimatedGradientHeader(
      padding: const EdgeInsets.all(AppSpacing.lg2),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 28,
            backgroundColor: AppColors.white,
            child: Icon(
              Icons.local_laundry_service_rounded,
              color: AppColors.primary,
              size: 30,
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome back',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.white,
                  ),
                ),
                const SizedBox(height: 3),
                const Text(
                  'Staff Workspace',
                  style: TextStyle(
                    color: AppColors.white,
                    fontSize: 23,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  "Today's laundry operations",
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
```

- [ ] **Step 3: Change `_SummaryCard.value` to `int` and render via `CountUpText`**

In `_SummaryCard`, change the field declaration `final String value;` to:

```dart
  final int value;
```

Then in `_SummaryCard.build`, replace the `Text(value, style: textTheme.headlineMedium)` with:

```dart
                  CountUpText(
                    value: value,
                    style: textTheme.headlineMedium,
                  ),
```

- [ ] **Step 4: Pass ints (not strings) at every `_SummaryCard` call site**

In `_SummaryGrid.build`, update the five `_SummaryCard(...)` calls so `value:` receives the int directly:

```dart
              child: _SummaryCard(
                title: 'Assigned',
                value: totalOrders,
                icon: Icons.assignment_outlined,
              ),
```
```dart
              child: _SummaryCard(
                title: OrderStatus.pendingPickup.label,
                value: pendingPickup,
                icon: Icons.local_shipping_outlined,
              ),
```
```dart
              child: _SummaryCard(
                title: OrderStatus.inProgress.label,
                value: inProgress,
                icon: Icons.timelapse_rounded,
              ),
```
```dart
              child: _SummaryCard(
                title: OrderStatus.readyForDelivery.label,
                value: readyForDelivery,
                icon: Icons.checkroom_outlined,
              ),
```
```dart
        _SummaryCard(
          title: 'Completed today',
          value: completed,
          icon: Icons.check_circle_outline_rounded,
          wide: true,
        ),
```

- [ ] **Step 5: Wrap dashboard content blocks in staggered `RevealOnMount`**

Replace `_DashboardBody.build` with this version (a local `reveal()` helper assigns increasing, index-capped delays so a long order list doesn't leave the last cards waiting seconds):

```dart
  @override
  Widget build(BuildContext context) {
    final totalOrders = orders.length;
    final pendingPickup = orders.countByStatus(OrderStatus.pendingPickup);
    final inProgress = orders.countByStatus(OrderStatus.inProgress);
    final readyForDelivery = orders.countByStatus(OrderStatus.readyForDelivery);
    final completed = orders.countByStatus(OrderStatus.completed);

    // Stagger the entrance: each content block reveals shortly after the
    // previous. The delay index is capped so long lists still appear promptly.
    var step = 0;
    Widget reveal(Widget child) {
      final cappedStep = step < 8 ? step : 8;
      step++;
      return RevealOnMount(
        delay: AppMotion.stagger * cappedStep,
        child: child,
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.sm,
        AppSpacing.xl,
        AppSpacing.xxl,
      ),
      children: [
        reveal(const _DashboardHeader()),
        const SizedBox(height: AppSpacing.xl),
        reveal(_SummaryGrid(
          totalOrders: totalOrders,
          pendingPickup: pendingPickup,
          inProgress: inProgress,
          readyForDelivery: readyForDelivery,
          completed: completed,
        )),
        const SizedBox(height: AppSpacing.xxl),
        reveal(_QuickActions(
          onNewPickup: onNewPickup,
          onShowReport: onShowReport,
          onCheckOrder: onCheckOrder,
        )),
        const SizedBox(height: AppSpacing.xxl),
        reveal(Text(
          'Assigned orders',
          style: Theme.of(context).textTheme.titleLarge,
        )),
        const SizedBox(height: AppSpacing.md),
        for (final order in orders) ...[
          reveal(OrderCard(order: order, onTap: () => onOrderTap(order))),
          const SizedBox(height: AppSpacing.md),
        ],
      ],
    );
  }
```

- [ ] **Step 6: Enable reduce-motion in the dashboard test pump helper**

In `test/dashboard/staff_dashboard_screen_test.dart`, change the `MaterialApp`'s `home:` inside `pumpDashboardWithDb` so the screen sees reduce-motion (keeps the forever-looping gradient from blocking `pumpAndSettle`). Replace:

```dart
      child: MaterialApp(
        home: StaffDashboardScreen(retrieveLostPhoto: () async => lostPhoto),
      ),
```

with:

```dart
      child: MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child:
                StaffDashboardScreen(retrieveLostPhoto: () async => lostPhoto),
          ),
        ),
      ),
```

- [ ] **Step 7: Add a content-after-settle test**

Add this test to `main()` in `test/dashboard/staff_dashboard_screen_test.dart` (the motion wrappers must not hide content):

```dart
  testWidgets('dashboard renders header, stats and quick actions after settle',
      (tester) async {
    await pumpDashboardWithDb(tester);

    expect(find.text('Staff Workspace'), findsOneWidget);
    expect(find.text('Quick actions'), findsOneWidget);
    expect(find.text('Assigned'), findsOneWidget);
  });
```

- [ ] **Step 8: Run the dashboard test to verify it passes**

Run: `flutter test test/dashboard/staff_dashboard_screen_test.dart`
Expected: PASS (all existing tests + the new content test).

- [ ] **Step 9: Verify the whole feature analyses clean**

Run: `flutter analyze lib/src/dashboard/staff_dashboard_screen.dart lib/src/shared/motion lib/src/shared/theme/app_motion.dart lib/src/shared/theme/app_card.dart`
Expected: `No issues found!`

- [ ] **Step 10: Commit**

```bash
git add lib/src/dashboard/staff_dashboard_screen.dart test/dashboard/staff_dashboard_screen_test.dart
git commit -m "feat(motion): wire reveals, count-up and gradient header into dashboard"
```

---

## Final verification

- [ ] Run each new/changed test file individually (one at a time on this host):
  - `flutter test test/shared/motion/pressable_scale_test.dart`
  - `flutter test test/shared/motion/reveal_on_mount_test.dart`
  - `flutter test test/shared/motion/count_up_text_test.dart`
  - `flutter test test/shared/motion/animated_gradient_header_test.dart`
  - `flutter test test/shared/theme/app_card_test.dart`
  - `flutter test test/dashboard/staff_dashboard_screen_test.dart`
  Expected: all PASS.
- [ ] `flutter analyze` → `No issues found!`
- [ ] Manually launch the app and confirm: header has a subtle moving sheen, stats count up, sections fade/slide in on opening Home, and cards scale slightly on press. Toggle the OS "reduce motion" setting and confirm everything renders statically.

---

## Spec coverage check

| Spec item | Task |
|---|---|
| `AppMotion` tokens (plain static class) | Task 1 |
| `RevealOnMount` staggered entrance | Task 3, wired in Task 7 (Step 5) |
| `CountUpText` stat numbers | Task 4, wired in Task 7 (Steps 3–4) |
| `AnimatedGradientHeader` subtle sheen | Task 5, wired in Task 7 (Step 2) |
| `PressableScale` app-wide press | Task 2, wired in Task 6 |
| Reduce-motion honoured (all four) | Tasks 2–5 (each has a reduce-motion test) |
| Reveal replays every Home open | Task 7 (Step 5) — `RevealOnMount` runs on each mount of `_DashboardBody` |
| Per-widget tests + dashboard content test | Tasks 2–5, Task 6, Task 7 (Step 7) |
