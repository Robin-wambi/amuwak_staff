# Theming Refactor (light mode) — Design

Date: 2026-05-31
Status: Approved for planning
Scope owner: raymond.suuna

## Problem

The app has a centralized Material 3 theme (`lib/src/shared/widgets/app_theme.dart`)
built on `ColorScheme.fromSeed`, but screens bypass it: ~50 sites hardcode raw
colors (`Colors.black54`, `Colors.white70`, `amuwakWhite`), inline
`TextStyle(fontSize: …)` instead of `textTheme` roles, magic-number spacing/radii,
and re-implement the same white "card" `BoxDecoration` ~21 times across five
screens. Order-status colors live inside the `OrderStatus` enum rather than the
theme, and the status chip renders same-hue text on a 12%-alpha tint of itself —
a WCAG contrast failure. The central theme is therefore largely decorative.

This refactor makes the theme the single source of truth for color, type,
spacing, radius, card styling, and status colors.

## Out of scope (explicitly)

- **Dark theme / `themeMode`.** Light mode only. No `darkTheme`. (User decision.)
- Accessibility work beyond the status-chip contrast fix (Semantics, touch
  targets, text-scale layout hardening) — separate later sub-project.
- UX flow changes (form validation, success states, empty states) — separate.
- i18n, `orderCode`-vs-UUID display, "last synced" — separate.

## Architecture

New folder `lib/src/shared/theme/` holds the design system. The existing
`lib/src/shared/widgets/app_theme.dart` becomes the assembler that wires the
tokens into `ThemeData`. (It stays at its current path so the `main.dart` import
and `buildAmuwakTheme()` entry point are unchanged.)

**Hybrid token strategy** (user-chosen):
- `static const` classes for spacing and radii (compile-time, zero ceremony).
- `ThemeExtension` for status colors (lives in the theme tree, contrast-checked).
- `ThemeData` slots (`CardTheme`, `textTheme`, `inputDecorationTheme`) for the rest.

### New files

| File | Contents |
|------|----------|
| `lib/src/shared/theme/app_colors.dart` | Raw brand palette moved from `app_theme.dart` (`amuwakPrimary`, `amuwakSurfaceBrand`, `amuwakDark`, `amuwakBackground`, `amuwakWhite`) **plus** new semantic constants for values currently hardcoded inline: `secondaryText` (replaces `Colors.black54`/`white70` body-secondary use) and `cardBorder` (the `amuwakPrimary.withValues(alpha:0.18)` hairline). |
| `lib/src/shared/theme/app_spacing.dart` | `class AppSpacing { static const double xs=4, sm=8, md=12, lg=16, xl=20, xxl=24; }` |
| `lib/src/shared/theme/app_radii.dart` | `class AppRadii { static const double field=18, card=22, chip=999; }` — consolidates the observed 14/15/16/18/20/22/24 sprawl onto a small set. |
| `lib/src/shared/theme/status_colors.dart` | `@immutable class StatusColors extends ThemeExtension<StatusColors>` carrying, for each `OrderStatus`, a `(color, onColor)` pair where `onColor` is a verified ≥4.5:1 text color for the tinted chip background. Also carries the sync-banner state pairs (error/offline/pending bg+fg). Provides `StatusColors.of(OrderStatus)` and the required `copyWith`/`lerp`. |
| `lib/src/shared/theme/app_card.dart` | `AppCard` — a thin wrapper over Material `Card` that consumes `CardTheme` (radius `AppRadii.card`, `cardBorder` side, `AppSpacing.lg` padding). Replaces duplicated `BoxDecoration` containers. |

### Rewritten file

`lib/src/shared/widgets/app_theme.dart` — assembles the above:
- **Trimmed `ColorScheme.fromSeed`:** keep `seedColor: amuwakPrimary`. Drop the
  redundant `secondary: amuwakPrimary` / `onSecondary` (secondary === primary is
  meaningless) and the manual `surface`/`onSurface` pins; let the algorithm
  generate them. Keep only brand-critical overrides (`primary`, `onPrimary`, and
  `primaryContainer`/`onPrimaryContainer` for the terracotta brand surface).
  Verify the orange-button text contrast that `onPrimary: amuwakDark` was
  compensating for still passes after trimming.
- **Complete `TextTheme` ramp:** beyond the current
  `headlineLarge/Medium/titleLarge/bodyMedium`, add the roles screens actually
  need so inline `fontSize:` literals can map to tokens — `titleLarge` for the
  recurring `fontSize:21` section headers, `headlineMedium`/`displaySmall` for
  metric numbers, `bodySmall` for captions.
- **`CardTheme`** with `AppRadii.card` shape + `cardBorder` side.
- **Register `StatusColors`** in `ThemeData.extensions`.
- NavigationBar/input/button themes keep their behavior but draw radii from
  `AppRadii` and the unselected-item color from `AppColors.secondaryText`.

## The one behavioral change: status colors leave the enum

`lib/src/orders/order_status.dart` currently embeds `Color` in each enum value.
To move colors into the theme:

- The `OrderStatus` enum **drops its `color` field** (keeps `label`,
  `toDbString`, `nextStatus`).
- `StatusColors.of(status)` returns the `(color, onColor)` pair.
- The two call sites change from `order.status.color` to
  `Theme.of(context).extension<StatusColors>()!.of(order.status)`:
  - `lib/src/orders/order_details_screen.dart:202`
  - `lib/src/dashboard/staff_dashboard_screen.dart:977`
- **Contrast fix applied here:** the chip at
  `staff_dashboard_screen.dart:1059-1065` renders `statusColor` text on
  `statusColor.withValues(alpha:0.12)`. The new `onColor` is a verified ≥4.5:1
  pair against that tint, fixing WCAG 1.4.3 for the chips.

## Migration order (bottom-up, each commit compiles & tests green)

Per the project workflow (TDD, one commit per task):

1. **Tokens** — add `app_colors.dart` (move brand constants; re-export or update
   the `app_theme.dart` references), `app_spacing.dart`, `app_radii.dart`. Pure
   additions; existing code keeps working via the moved constants.
2. **StatusColors** — add the extension with a contrast test, register it in the
   theme, then migrate the `OrderStatus` enum + its 2 call sites + the chip
   contrast fix.
3. **AppCard** — add `AppCard` + `CardTheme` + widget test, then swap the
   duplicated `BoxDecoration`s (`BoxDecoration` occurrences: dashboard 10,
   reports 5, details 4, delivery-capture 3, pickup-capture 2 — not all are
   cards; only the white "container" pattern migrates, decorative
   gradients/overlays stay).
4. **app_theme.dart rewrite** — trimmed scheme + full `TextTheme` + theme-builder
   unit test.
5. **Screen sweep** — replace inline `Colors.black54`/`white70`/`amuwakWhite` and
   `TextStyle(fontSize:…)` with `colorScheme.*`/`textTheme.*` roles and spacing
   tokens, one screen per commit. `staff_dashboard_screen.dart` (1115 lines) is
   its own commit; `daily_report_screen.dart`, `order_details_screen.dart`,
   `login_screen.dart`, capture screens, `sync_status_banner.dart` follow.

## Testing (logic + widget, no goldens)

Per Windows-host constraint, run single test files individually.

- **Theme builder unit test:** `buildAmuwakTheme()` produces the expected
  `colorScheme` roles, registers `StatusColors`, and exposes the `CardTheme`
  shape/border.
- **Contrast assertion:** a helper computes WCAG relative-luminance contrast;
  assert every `StatusColors` `(onColor, tint)` pair and the sync-banner fg/bg
  pairs are ≥4.5:1. This is the regression guard for the chip bug.
- **AppCard widget test:** pumped inside the theme, `AppCard` renders with the
  `CardTheme` radius and border (no hardcoded `BoxDecoration`).
- **Status mapping test:** `StatusColors.of` returns a defined pair for all four
  `OrderStatus` values (exhaustiveness).

## Risks / notes

- Removing `color` from `OrderStatus` is a breaking change to that file's public
  shape; the grep above confirms only 2 read sites, both screens, both migrated
  in the same step.
- Trimming `fromSeed` overrides changes generated `surface`/`secondary` tones
  slightly; the screen sweep (step 5) is where any resulting visual drift is
  reconciled against roles, so steps 4–5 land together visually.
- `CardTheme` vs `CardThemeData`: use whichever the installed Flutter version
  expects (verify at implementation time).
