# 60-30-10 Brand Color Refresh

**Date:** 2026-05-27
**Scope:** Theme-level color refactor in [lib/src/shared/widgets/app_theme.dart](../../../lib/src/shared/widgets/app_theme.dart) plus targeted verification of two screens.
**Goal:** Align the app's main brand color with the logo and apply the 60-30-10 design rule, using the logo orange as the 10% accent (industry best practice for delivery/courier apps and Material 3).

---

## Background

The current theme uses `amuwakPrimary = #A85A1F` — a muted terracotta that does not match the logo. Pixel sampling of [assets/branding/app_icon.png](../../../assets/branding/app_icon.png) shows the dominant logo orange is `#FF6E11` (7,838 pixels — overwhelmingly dominant).

The user requested applying the 60-30-10 design rule. After researching industry patterns (Spotify, Swiggy, Material 3 guidance) and verifying WCAG AA contrast requirements, we landed on **orange-as-10%** rather than orange-as-30%, for two reasons:

1. **Best practice:** General 60-30-10 (UX Planet, LogRocket, Antikode) and food-delivery-specific guidance (Zeew, MoldStud) consistently place the brand color in the 10% role — concentrated on CTAs, badges, and active states, not blanketing app bars. Material 3's `primary` role likewise lives on small surfaces like FABs.
2. **Contrast:** Pure logo orange `#FF6E11` on white has only ~2.8:1 contrast — below WCAG AA's 4.5:1 for normal text. White text on `#FF6E11` also fails. Reserving `#FF6E11` for accents (where contrast bites less) and using a darker logo-family terracotta on large surfaces preserves the brand while clearing accessibility.

---

## Palette

| Role | Color | Hex | Where it lives |
|---|---|---|---|
| **60% Dominant** | Cream / White | `#FFF8F2` scaffold, `#FFFFFF` cards | Backgrounds, card surfaces, input fills |
| **30% Secondary (brand family)** | Deep Terracotta | `#C75A0E` | AppBar, hero panels, large section banners. White text on it = ~5.7:1, passes AA |
| **10% Accent (pure logo)** | Logo Orange | `#FF6E11` | FAB, primary buttons, badges, status pills, active tab indicator, focus rings, key icons |
| **Text + secondary CTAs** | Charcoal | `#1F1F1F` | Body text, secondary outlined buttons, icon defaults. Use as text color *on* `#FF6E11` |

**Retired:** `amuwakSoftAccent = #F3E0D0` is deleted from [app_theme.dart](../../../lib/src/shared/widgets/app_theme.dart). If a future surface needs a peach tint, re-add it explicitly at that time.

**Replaced:** `amuwakPrimary = #A85A1F` becomes `#FF6E11`. A new constant `amuwakSurfaceBrand = #C75A0E` is added for the 30% role.

---

## Material 3 ColorScheme mapping

```dart
const Color amuwakPrimary = Color(0xFFFF6E11);        // logo orange (10%)
const Color amuwakSurfaceBrand = Color(0xFFC75A0E);   // deep terracotta (30%)
const Color amuwakDark = Color(0xFF1F1F1F);           // text + dark CTAs (unchanged)
const Color amuwakBackground = Color(0xFFFFF8F2);     // scaffold (unchanged)
const Color amuwakWhite = Color(0xFFFFFFFF);          // card surface (unchanged)

ColorScheme.fromSeed(
  seedColor: amuwakPrimary,             // #FF6E11
  primary: amuwakPrimary,               // #FF6E11
  onPrimary: amuwakDark,                // dark text on bright orange — fixes white-text contrast issue
  primaryContainer: amuwakSurfaceBrand, // #C75A0E — the 30% surface
  onPrimaryContainer: amuwakWhite,
  secondary: amuwakDark,                // charcoal secondary
  onSecondary: amuwakWhite,
  surface: amuwakWhite,
  onSurface: amuwakDark,
)
```

### Component themes

- **AppBarTheme** (new): background `amuwakSurfaceBrand`, foreground white, elevation 0. Current code uses default — AppBars currently render with the seed color, so this needs to be set explicitly to lock in the 30% role.
- **ElevatedButtonTheme**: background `amuwakPrimary` (`#FF6E11`), **foreground `amuwakDark`** (was white — this is the accessibility fix). Keep `minimumSize`, `shape`, `borderRadius` as-is.
- **InputDecorationTheme**: focused border `amuwakPrimary`, prefix icon `amuwakPrimary`. No change.
- **FloatingActionButtonTheme** (new): background `amuwakPrimary`, foreground `amuwakDark`.
- **TextTheme**: no changes (already uses `amuwakDark`).

---

## Screen-level expectations

Of the 11 screens, 9 inherit cleanly from the updated `ColorScheme`. Two need manual verification because they hand-roll colors or compose multiple surfaces:

- **[login_screen.dart](../../../lib/src/auth/login_screen.dart)** — inspect for any hand-rolled colors (gradients, overlays, brand-mark backdrops) that reference the old tokens directly or use literal hex values. Confirm the primary "Sign in" button shows dark `#1F1F1F` text on `#FF6E11`, not white.
- **[staff_dashboard_screen.dart](../../../lib/src/dashboard/staff_dashboard_screen.dart)** — inspect any hand-rolled tile/card colors. Ensure large hero surfaces (if present) use `amuwakSurfaceBrand` (the 30% terracotta) and only small action chips/badges use `amuwakPrimary` (the 10% orange), not the reverse.

The remaining screens are verified by visual inspection only after the theme swap — no code changes expected:

- [order_search_screen.dart](../../../lib/src/orders/order_search_screen.dart)
- [order_details_screen.dart](../../../lib/src/orders/order_details_screen.dart)
- [new_pickup_screen.dart](../../../lib/src/orders/new_pickup_screen.dart)
- [scanner_screen.dart](../../../lib/src/orders/proof/scanner_screen.dart)
- [pickup_capture_screen.dart](../../../lib/src/orders/proof/pickup_capture_screen.dart)
- [delivery_capture_screen.dart](../../../lib/src/orders/proof/delivery_capture_screen.dart)
- [notifications_screen.dart](../../../lib/src/notifications/notifications_screen.dart)
- [daily_report_screen.dart](../../../lib/src/reports/daily_report_screen.dart)
- [sync_errors_screen.dart](../../../lib/src/sync/sync_errors_screen.dart)

---

## Accessibility checks (WCAG AA targets)

| Pair | Contrast | Status |
|---|---|---|
| White on `#C75A0E` (app bar text) | ~5.7:1 | Pass AA normal text |
| `#1F1F1F` on `#FF6E11` (button label) | ~5.0:1 | Pass AA normal text |
| `#1F1F1F` on `#FFF8F2` (body text on bg) | ~16:1 | Pass AAA |
| `#1F1F1F` on `#FFFFFF` (body text on card) | ~16:1 | Pass AAA |
| `#FF6E11` on `#FFFFFF` (focus rings, icons, large headings only) | ~2.8:1 | Pass for 3:1 UI components only — never use for normal body text |

**Rule of thumb baked into the palette:** never use orange `#FF6E11` for body text or small labels on light backgrounds. It's reserved for surfaces, icons, focus rings, and large display text where the 3:1 UI-component threshold applies.

---

## Acceptance criteria

1. `amuwakPrimary` constant equals `#FF6E11` and `amuwakSurfaceBrand = #C75A0E` exists in [app_theme.dart](../../../lib/src/shared/widgets/app_theme.dart).
2. `ColorScheme` and component themes reflect the mapping above (including AppBar background, ElevatedButton dark foreground, FAB).
3. All 11 screens render without compile errors and visually preserve their layout. No screen displays white text on `#FF6E11`.
4. The login screen and dashboard pass manual visual review against the design intent (30% terracotta chrome, 10% orange accent).
5. Existing tests still pass (`flutter test` per-file; see project memory regarding the multi-file hang on this Windows host).

---

## Out of scope (YAGNI)

- Dark-mode variant (single light theme today; can be added later from these same tokens).
- Typography or font changes.
- Icon or asset swaps.
- Screen redesigns beyond the two manual-verification screens.
- Animation, transition, or motion changes.
