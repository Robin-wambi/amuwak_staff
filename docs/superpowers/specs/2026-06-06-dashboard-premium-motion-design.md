# Dashboard Premium Motion — Design

**Date:** 2026-06-06
**Branch:** feat/ui-foundation-typography-elevation (or a follow-on)
**Status:** Approved (brainstorming) — pending implementation plan

## Goal

Make the staff dashboard feel premium through restrained, purposeful motion,
in the spirit of Canva's design language. Four composable effects, built with
native Flutter (no new dependency), respecting accessibility.

This builds on the in-flight typography + elevation theming refactor and is
informed by deep research into Canva's design guidelines and Material 3. Two
research findings shape it directly:

- **Restraint for an operations tool.** A field rider tool prioritizes
  at-a-glance legibility and scan-speed; motion must never compete with
  content or hurt performance on lower-end devices. → the gradient is a
  *subtle* sheen, entrance reveals are fast (~600ms total), nothing loops
  loudly.
- **Motion as tokens.** M3 has no verified ready-made motion-token package
  (the one candidate was refuted in research), so durations/curves come
  straight from the M3 spec, centralized in one tokens file — consistent with
  the existing `AppSpacing` / `AppElevation` / `AppRadii` pattern.

## Non-goals (YAGNI)

- No `flutter_animate` / Rive / Lottie / any new package.
- No animated route/page transitions.
- No shimmer skeleton loaders.
- No theme-wide motion `ThemeExtension` yet (deferred; plain static class now,
  can migrate with the broader theme refactor later).

## Decisions (locked during brainstorming)

| Question | Decision |
|---|---|
| Implementation | Native Flutter, reusable widgets (zero new deps) |
| Effects | All four: staggered reveal, count-up, animated gradient, press scale |
| Gradient intensity | **Subtle living sheen** — low-contrast terracotta, ~6s loop |
| Entrance replay | **Every time the Home tab opens** (plays on each mount) |
| Motion tokens | **Plain static class** `AppMotion` (matches existing token files) |

## Architecture

### 1. Motion tokens — `lib/src/shared/theme/app_motion.dart`

A new `abstract final class AppMotion`, sibling to `AppSpacing`/`AppElevation`/
`AppRadii`. Single source for every duration, curve, and stagger value.
Values sourced from the M3 motion spec, kept conservative:

- `fast` = 150ms — press feedback.
- `medium` = 320ms — single reveal / per-step.
- `slow` = 600ms — count-up total duration.
- `gradientLoop` = 6s — gradient sheen cycle.
- `stagger` = 80ms — delay between sibling reveals.
- `standard` = `Curves.easeOutCubic` — reveals.
- `emphasized` = `Curves.easeInOut` — gradient lerp.
- `revealOffset` = 16.0 — upward slide distance (logical px).
- `pressScale` = 0.97 — pressed scale factor.

### 2. Reusable motion widgets — `lib/src/shared/motion/`

A new directory holding four independent, testable widgets. Each is
self-contained, owns its own `AnimationController` where needed (disposed
correctly), and reads tokens from `AppMotion`.

#### `RevealOnMount` (`reveal_on_mount.dart`)
- Wraps a `child`; on mount, fades 0→1 and slides up `revealOffset`→0 over
  `medium` with `standard` curve.
- Constructor takes `delay` (default `Duration.zero`) so callers stagger
  siblings: `RevealOnMount(delay: AppMotion.stagger * index, child: ...)`.
- `StatefulWidget` + single `AnimationController`. Starts after `delay` via a
  guarded post-frame / `Future.delayed` that checks `mounted`.
- Reduced motion: shows the final state immediately (no animation, no delay).

#### `CountUpText` (`count_up_text.dart`)
- `TweenAnimationBuilder<double>` from 0 → `value` over `slow`, `standard`
  curve, rendered as `value.round().toString()` with the supplied `style`.
- `value` is an `int`; when it changes (e.g. a new order arrives), the tween
  re-runs from the previous displayed value to the new one (implicit-animation
  behavior — animates from old to new, not 0).
- Reduced motion: renders the final value with no tween (`duration: Duration.zero`).

#### `AnimatedGradientHeader` (`animated_gradient_header.dart`)
- Replaces the flat `surfaceBrand` container background in `_DashboardHeader`.
- Repeating `AnimationController` (`gradientLoop`, `reverse`/ping-pong) drives a
  `LinearGradient` whose two stops lerp between `surfaceBrand` and a slightly
  lighter terracotta (e.g. `surfaceBrand` blended toward white ~8–12%), low
  contrast so it reads as a living surface, not a flashy gradient.
- Preserves the existing `AppRadii.card` corner and the soft brand shadow.
- Exposes the same padding/child contract the current header uses so swap-in is
  mechanical.
- Reduced motion: paints a single static frame of the gradient (controller not
  started).

#### `PressableScale` (`pressable_scale.dart`)
- Wraps a tappable surface; on tap-down scales to `pressScale`, springs back to
  1.0 on tap-up/cancel via `AnimatedScale` over `fast`.
- Takes `onTap` and `child`; forwards the tap. Used so the press polish is
  reusable app-wide, not dashboard-only.
- Reduced motion: no scale; passes the tap straight through.

### 3. Wiring into the dashboard — `staff_dashboard_screen.dart`

- `_DashboardBody`: wrap each top-level child in `RevealOnMount` with an
  increasing `delay` (index 0..n): header → `_SummaryGrid` → `_QuickActions` →
  "Assigned orders" heading → each `OrderCard`. Reveal replays on every mount
  of the Home tab (per the locked decision — the body is reconstructed on tab
  return, which naturally re-triggers).
- `_SummaryCard`: render `value` via `CountUpText` instead of plain `Text`.
- `_DashboardHeader`: swap the `Container`'s flat `color: surfaceBrand`
  decoration for `AnimatedGradientHeader`.
- `_DashboardLoadingBody`: same reveal treatment for the header + quick actions
  it shows, so the loading state matches.

### 4. App-wide press polish (low-risk, high-value)

- `AppCard`: when `onTap != null`, wrap the tap path in `PressableScale` (the
  card already only builds an `InkWell` when tappable — the scale composes with
  the existing ink ripple).
- `_ActionButton` (quick actions) already routes through `AppCard(onTap:)`, so
  it inherits the press scale for free.

This means the press micro-interaction lands consistently on every tappable
card across the app, not just the dashboard.

## Accessibility (non-negotiable)

Every widget checks `MediaQuery.of(context).disableAnimations` (the OS
"reduce motion" setting). When true:
- `RevealOnMount` → final state instantly, no delay.
- `CountUpText` → final number, no tween.
- `AnimatedGradientHeader` → static gradient frame.
- `PressableScale` → no scale.

This is the line between "premium" and "annoying," and it keeps the field tool
usable for motion-sensitive users.

## Error / edge handling

- Controllers guarded with `mounted` checks around delayed starts; disposed in
  `dispose()`.
- `CountUpText` handles `value` changing mid-flight (orders streaming in) by
  animating from the current value.
- Reveal `delay` for long order lists is capped conceptually by index, but
  since only the visible `ListView` children build, off-screen cards reveal as
  they scroll into view on first build — acceptable; no special handling.

## Testing

Per project convention (TDD, one test file at a time on this Windows host):

- `test/shared/motion/reveal_on_mount_test.dart` — child present and opaque
  after `pumpAndSettle`; reduced-motion (`MediaQuery(disableAnimations: true)`)
  renders final state on first frame.
- `test/shared/motion/count_up_text_test.dart` — lands on the exact target
  number after settle; reduced-motion shows the number immediately; updating
  `value` re-animates to the new number.
- `test/shared/motion/animated_gradient_header_test.dart` — renders child;
  reduced-motion path builds without starting a repeating controller (no
  pending timers).
- `test/shared/motion/pressable_scale_test.dart` — forwards `onTap`;
  reduced-motion passes tap through with no scale.
- Extend the existing dashboard test to assert dashboard content (header text,
  stat values, quick actions) is present after `pumpAndSettle`, proving the
  motion wrappers don't hide content.

All new test files run as single-file `flutter test <path>` invocations.

## Files touched

**New:**
- `lib/src/shared/theme/app_motion.dart`
- `lib/src/shared/motion/reveal_on_mount.dart`
- `lib/src/shared/motion/count_up_text.dart`
- `lib/src/shared/motion/animated_gradient_header.dart`
- `lib/src/shared/motion/pressable_scale.dart`
- `test/shared/motion/*_test.dart` (4 files)

**Modified:**
- `lib/src/dashboard/staff_dashboard_screen.dart` (wire reveals, count-up, gradient)
- `lib/src/shared/theme/app_card.dart` (press scale on tappable path)
- `test/dashboard/staff_dashboard_screen_test.dart` (content-after-settle assertions)
