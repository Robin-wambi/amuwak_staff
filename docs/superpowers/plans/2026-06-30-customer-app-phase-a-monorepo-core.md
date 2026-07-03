# Customer App — Phase A: Monorepo + `amuwak_core` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert the single-package `amuwak_staff` repo into a Dart pub workspace with a shared `amuwak_core` package, and move the pure, app-agnostic code (design system, utilities, domain + pricing logic, auth, bootstrap) into it — with the staff app fully building and all its tests green at every step.

**Architecture:** Native Dart pub workspaces (shared lockfile, single resolution) + Melos for task running across packages. The staff app stays at the repo root and becomes the workspace root; `packages/amuwak_core` is a new member it depends on. Extractions happen in small batches, each verified by the (moved) existing tests plus `flutter analyze`. No behavior changes — this is a pure refactor that unlocks the later customer-app plans.

**Tech Stack:** Flutter (Dart `^3.8.0`), `flutter_riverpod`, `supabase_flutter`, Melos, `flutter_test` + `mocktail`.

## Global Constraints

- Dart SDK floor: `^3.8.0` (every package's `environment.sdk`). Verbatim from root `pubspec.yaml:22`.
- The shared package is named `amuwak_core`; its import prefix is `package:amuwak_core/`.
- `amuwak_core` MUST NOT import from `amuwak_staff` (or any app). Apps depend on packages; packages never depend on apps.
- `amuwak_core` MUST NOT depend on Drift (`drift`, `drift_flutter`, `sqlite3*`) — it is the Drift-free layer.
- The staff app keeps its name `amuwak_staff` and stays at the repo root (do not relocate to `apps/`).
- This Windows host hangs on multi-path `flutter test a b`; run the **whole package** suite (`flutter test`) or a **single file** (`flutter test path`), never multiple explicit paths. (project memory: "Flutter test one file at a time")
- `git push` requires the sandbox disabled; commits in this plan are local only (no push step). Pass explicit paths to `git commit -- <paths>` to avoid bundling unrelated pre-staged work. (project memory: "Scoped git commits")
- Brand font "Plus Jakarta Sans" is bundled by the **staff app** pubspec (`pubspec.yaml:105-117`); `app_typography.dart` only names the family, so the font assets stay declared in each consuming app's pubspec — `amuwak_core` does not bundle fonts.

---

## File Structure

New files:
- `melos.yaml` — workspace task runner config.
- `packages/amuwak_core/pubspec.yaml` — the shared package manifest (`resolution: workspace`).
- `packages/amuwak_core/lib/amuwak_core.dart` — barrel that re-exports the public API.
- `packages/amuwak_core/lib/src/**` — the moved sources, preserving their `shared/…`, `orders/…`, `auth/…`, `bootstrap/…` subpaths.
- `packages/amuwak_core/test/**` — the moved tests, mirroring the moved sources.
- `packages/amuwak_core/analysis_options.yaml` — same lint set as the app.
- `.github/workflows/test.yml` — runs `melos run test` + `melos run analyze` on PR/push.

Modified:
- `pubspec.yaml` (root / staff app) — add `workspace:` list + `amuwak_core` path dep.
- ~66 staff-app `.dart` files — rewrite imports of moved symbols to `package:amuwak_core/amuwak_core.dart`.

Stays in the staff app (NOT moved — staff/offline coupled): `lib/src/shared/widgets/sync_status_banner.dart` (sync-state UI), everything under `lib/src/data/`, `lib/src/sync/` (except the model split deferred to the customer-app plan), `printing/`, `reports/`, `expenses/`, `dashboard/`, proof capture/scanner, staff invite.

---

## Out of scope for Phase A (handoff to the customer-app plan)
These need the Plan 2 backend or are higher-risk and are exercised directly by the customer app, so they are deferred and documented here so later plans can reference them:
- Splitting a **Drift-free `LaundryOrder` + `Customer`** domain model out of `lib/src/orders/order.dart` (keep `fromDriftRow` in the staff app via an extension); moving `supabase_mappers.dart` + `supabase_payloads.dart`.
- Extracting the repository/provider base pattern (`watchAll/watchById/.stream()`-then-join).
- The new shared `OrderMessagesRepository` (depends on the `order_messages` table from Plan 2).

---

### Task 1: Create the pub workspace + empty `amuwak_core`

**Files:**
- Create: `packages/amuwak_core/pubspec.yaml`, `packages/amuwak_core/lib/amuwak_core.dart`, `packages/amuwak_core/analysis_options.yaml`
- Modify: `pubspec.yaml` (root)

**Interfaces:**
- Produces: an empty `package:amuwak_core/amuwak_core.dart` library (barrel, initially with a placeholder export) that later tasks fill; a resolved workspace where `flutter pub get` at the root links `amuwak_core` by path.

- [ ] **Step 1: Create the shared package manifest**

Create `packages/amuwak_core/pubspec.yaml`:

```yaml
name: amuwak_core
description: Shared design system, utilities, domain and pricing logic for the Amuwak apps.
publish_to: 'none'
version: 0.1.0

environment:
  sdk: ^3.8.0

resolution: workspace

dependencies:
  flutter:
    sdk: flutter
  flutter_riverpod: ^2.5.0
  supabase_flutter: ^2.5.0
  uuid: ^4.5.0
  meta: ^1.15.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^5.0.0
  mocktail: ^1.0.4

flutter:
  uses-material-design: true
```

- [ ] **Step 2: Create the barrel and lint config**

Create `packages/amuwak_core/lib/amuwak_core.dart`:

```dart
/// Public API of the shared Amuwak core package.
///
/// Later tasks add `export 'src/...';` lines here as sources move in.
library;
```

Create `packages/amuwak_core/analysis_options.yaml`:

```yaml
include: package:flutter_lints/flutter.yaml
```

- [ ] **Step 3: Turn the repo root into the workspace root**

Edit `pubspec.yaml` (root). Directly after the `environment:` block (line 21-22), add the workspace list, and add the path dependency under `dependencies:` (alongside the existing deps):

```yaml
environment:
  sdk: ^3.8.0

workspace:
  - packages/amuwak_core
```

And under `dependencies:` add:

```yaml
  amuwak_core:
    path: packages/amuwak_core
```

- [ ] **Step 4: Resolve the workspace**

Run: `flutter pub get`
Expected: completes successfully; output mentions resolving both `amuwak_staff` and `amuwak_core`; a single root `pubspec.lock` is written/updated. No "path does not exist" errors.

- [ ] **Step 5: Verify the staff app still analyzes and tests green**

Run: `flutter analyze`
Expected: no new errors (same baseline as before).

Run: `flutter test`
Expected: the full existing staff suite PASSES (unchanged — nothing has moved yet).

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml pubspec.lock packages/amuwak_core/pubspec.yaml packages/amuwak_core/lib/amuwak_core.dart packages/amuwak_core/analysis_options.yaml
git commit -m "build: introduce pub workspace with empty amuwak_core package"
```

---

### Task 2: Add Melos + a CI test job

**Files:**
- Create: `melos.yaml`, `.github/workflows/test.yml`
- Modify: `pubspec.yaml` (root) — add `melos` dev dependency

**Interfaces:**
- Produces: `melos run test` and `melos run analyze` scripts that fan out across all workspace packages; a CI job that runs them.

- [ ] **Step 1: Add Melos as a dev dependency**

Edit root `pubspec.yaml` under `dev_dependencies:` and add:

```yaml
  melos: ^6.3.0
```

Run: `flutter pub get`
Expected: resolves with `melos` available.

- [ ] **Step 2: Create the Melos config**

Create `melos.yaml`:

```yaml
name: amuwak

packages:
  - .
  - packages/**

scripts:
  analyze:
    description: Analyze all packages.
    exec: flutter analyze
  test:
    description: Run tests in packages that have a test/ dir.
    run: flutter test
    exec:
      concurrency: 1
    packageFilters:
      dirExists: test
```

> Note: `concurrency: 1` keeps test runs serial, matching this host's one-suite-at-a-time constraint.

- [ ] **Step 3: Verify Melos sees both packages**

Run: `dart run melos list`
Expected: lists `amuwak_staff` and `amuwak_core`.

- [ ] **Step 4: Run the aggregate test + analyze scripts**

Run: `dart run melos run analyze`
Expected: analyze passes for both packages.

Run: `dart run melos run test`
Expected: staff suite passes; `amuwak_core` is skipped or passes (no tests yet — `dirExists: test` filter skips it until Task 3 adds `test/`).

- [ ] **Step 5: Create the CI workflow**

Create `.github/workflows/test.yml`:

```yaml
name: test

on:
  push:
    branches: [main]
  pull_request:

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
      - run: flutter pub get
      - run: dart run melos run analyze
      - run: dart run melos run test
```

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml pubspec.lock melos.yaml .github/workflows/test.yml
git commit -m "build: add melos task runner and CI test/analyze job"
```

---

### Task 3: Extract leaf utilities (`phone`, `uuid`, `format_ugx`, `order_code`, `email_validation`)

These five files have **no internal `lib/src` dependencies** (only Dart/Flutter SDK), so they move first.

**Files:**
- Move: `lib/src/shared/{phone,uuid,format_ugx,order_code,email_validation}.dart` → `packages/amuwak_core/lib/src/shared/`
- Move tests: `test/shared/{phone,uuid,format_ugx,order_code}_test.dart` (+ `email_validation` test if present) → `packages/amuwak_core/test/shared/`
- Modify: `packages/amuwak_core/lib/amuwak_core.dart` (barrel exports); staff files importing these symbols.

**Interfaces:**
- Produces (now under `package:amuwak_core/amuwak_core.dart`): `normalizePhone`, `ugandaNationalDigits` (phone.dart); `defaultUuidV7` (uuid.dart); `formatUgx`, `formatPct` (format_ugx.dart); `parseOrderCodeRpcResult`, `orderCodeNumber`, `isBareOrderNumber` (order_code.dart); `isValidEmail` (email_validation.dart).

- [ ] **Step 1: Move the source files (preserve content)**

```bash
git mv lib/src/shared/phone.dart            packages/amuwak_core/lib/src/shared/phone.dart
git mv lib/src/shared/uuid.dart             packages/amuwak_core/lib/src/shared/uuid.dart
git mv lib/src/shared/format_ugx.dart       packages/amuwak_core/lib/src/shared/format_ugx.dart
git mv lib/src/shared/order_code.dart       packages/amuwak_core/lib/src/shared/order_code.dart
git mv lib/src/shared/email_validation.dart packages/amuwak_core/lib/src/shared/email_validation.dart
```

- [ ] **Step 2: Export them from the barrel**

Edit `packages/amuwak_core/lib/amuwak_core.dart`, replacing the `library;` placeholder body with:

```dart
library;

export 'src/shared/phone.dart';
export 'src/shared/uuid.dart';
export 'src/shared/format_ugx.dart';
export 'src/shared/order_code.dart';
export 'src/shared/email_validation.dart';
```

- [ ] **Step 3: Move the matching tests and point them at the package**

```bash
git mv test/shared/phone_test.dart      packages/amuwak_core/test/shared/phone_test.dart
git mv test/shared/uuid_test.dart       packages/amuwak_core/test/shared/uuid_test.dart
git mv test/shared/format_ugx_test.dart packages/amuwak_core/test/shared/format_ugx_test.dart
git mv test/shared/order_code_test.dart packages/amuwak_core/test/shared/order_code_test.dart
```

In each moved test, change the import of the symbol-under-test to the barrel. For example in `packages/amuwak_core/test/shared/phone_test.dart` replace the existing `import '...phone.dart';` line with:

```dart
import 'package:amuwak_core/amuwak_core.dart';
```

(Repeat for the other three moved tests, each importing `package:amuwak_core/amuwak_core.dart`.)

- [ ] **Step 4: Rewrite staff-app imports of these symbols**

Run: `flutter analyze`
Expected: FAIL — a list of "Target of URI doesn't exist" / "undefined" errors in staff files that imported the moved files (e.g. `lib/src/orders/new_pickup_screen.dart`, `lib/src/sync/orders_repository.dart`, `lib/src/orders/widgets/order_card.dart`).

For every file the analyzer flags, replace its now-broken import of a moved util (whether relative like `import '../shared/phone.dart';` or absolute `package:amuwak_staff/src/shared/phone.dart`) with:

```dart
import 'package:amuwak_core/amuwak_core.dart';
```

Collapse duplicates if a file imported more than one moved util (a single barrel import covers all five). Re-run `flutter analyze` and repeat until it reports no errors.

- [ ] **Step 5: Verify both suites green**

Run: `flutter test` (staff app)
Expected: PASS.

Run: `cd packages/amuwak_core && flutter test && cd ../..`
Expected: the four moved util test files PASS under `amuwak_core`.

- [ ] **Step 6: Commit**

```bash
git add -A packages/amuwak_core lib test
git commit -m "refactor: move leaf utilities (phone, uuid, format_ugx, order_code, email_validation) to amuwak_core"
```

---

### Task 4: Extract the design-system tokens (`theme/`)

**Files:**
- Move: `lib/src/shared/theme/{app_colors,app_radii,app_spacing,app_elevation,app_motion,app_typography,status_colors,app_card}.dart` → `packages/amuwak_core/lib/src/shared/theme/`
- Move tests: `test/shared/theme/{app_colors,app_elevation,app_typography,status_colors,app_card,tokens}_test.dart` → `packages/amuwak_core/test/shared/theme/`
- Modify: barrel; staff imports of theme tokens.

**Interfaces:**
- Consumes: nothing outside `flutter/material` (these tokens are self-contained; `status_colors.dart` references the `OrderStatus` enum — see note in Step 4).
- Produces (via barrel): `AppColors`, `AppRadii`, `AppSpacing`, `AppElevation`, `AppMotion`, `AppTypography`, the `StatusColors` ThemeExtension, and the `AppCard` widget.

- [ ] **Step 1: Move the theme sources**

```bash
git mv lib/src/shared/theme/app_colors.dart     packages/amuwak_core/lib/src/shared/theme/app_colors.dart
git mv lib/src/shared/theme/app_radii.dart      packages/amuwak_core/lib/src/shared/theme/app_radii.dart
git mv lib/src/shared/theme/app_spacing.dart    packages/amuwak_core/lib/src/shared/theme/app_spacing.dart
git mv lib/src/shared/theme/app_elevation.dart  packages/amuwak_core/lib/src/shared/theme/app_elevation.dart
git mv lib/src/shared/theme/app_motion.dart     packages/amuwak_core/lib/src/shared/theme/app_motion.dart
git mv lib/src/shared/theme/app_typography.dart packages/amuwak_core/lib/src/shared/theme/app_typography.dart
git mv lib/src/shared/theme/status_colors.dart  packages/amuwak_core/lib/src/shared/theme/status_colors.dart
git mv lib/src/shared/theme/app_card.dart       packages/amuwak_core/lib/src/shared/theme/app_card.dart
```

- [ ] **Step 2: Add barrel exports**

Append to `packages/amuwak_core/lib/amuwak_core.dart`:

```dart
export 'src/shared/theme/app_colors.dart';
export 'src/shared/theme/app_radii.dart';
export 'src/shared/theme/app_spacing.dart';
export 'src/shared/theme/app_elevation.dart';
export 'src/shared/theme/app_motion.dart';
export 'src/shared/theme/app_typography.dart';
export 'src/shared/theme/status_colors.dart';
export 'src/shared/theme/app_card.dart';
```

- [ ] **Step 3: Fix intra-`amuwak_core` imports between moved files**

Run: `cd packages/amuwak_core && flutter analyze`
Expected: FAIL where a moved theme file imported a sibling via a relative path that still resolves (relative imports survive a move that preserves the directory) — but FAIL where any moved file referenced a still-in-staff file (e.g. `status_colors.dart` importing the `OrderStatus` enum from `lib/src/orders/order_status.dart`, which has NOT moved yet).

If `status_colors.dart` imports `OrderStatus`, this is a forward dependency on Task 6. Resolve by ordering: move `order_status.dart` and `service_type.dart` into `amuwak_core` **now** as part of this step (they are pure enums with no deps):

```bash
git mv lib/src/orders/order_status.dart  packages/amuwak_core/lib/src/orders/order_status.dart
git mv lib/src/orders/service_type.dart  packages/amuwak_core/lib/src/orders/service_type.dart
```

Append to the barrel:

```dart
export 'src/orders/order_status.dart';
export 'src/orders/service_type.dart';
```

Then update `status_colors.dart`'s import of the enum to a relative `import '../../orders/order_status.dart';` (now in-package). Re-run `cd packages/amuwak_core && flutter analyze` until clean.

- [ ] **Step 4: Move the theme tests**

```bash
git mv test/shared/theme/app_colors_test.dart     packages/amuwak_core/test/shared/theme/app_colors_test.dart
git mv test/shared/theme/app_elevation_test.dart  packages/amuwak_core/test/shared/theme/app_elevation_test.dart
git mv test/shared/theme/app_typography_test.dart packages/amuwak_core/test/shared/theme/app_typography_test.dart
git mv test/shared/theme/status_colors_test.dart  packages/amuwak_core/test/shared/theme/status_colors_test.dart
git mv test/shared/theme/app_card_test.dart       packages/amuwak_core/test/shared/theme/app_card_test.dart
git mv test/shared/theme/tokens_test.dart         packages/amuwak_core/test/shared/theme/tokens_test.dart
```

In each moved test, replace imports of the moved symbols with `import 'package:amuwak_core/amuwak_core.dart';`.

- [ ] **Step 5: Rewrite staff-app imports**

Run: `flutter analyze` (repo root / staff app)
Expected: FAIL listing staff files that imported any moved theme token or the two enums.

For each flagged staff file, replace the broken theme/enum imports with `import 'package:amuwak_core/amuwak_core.dart';` (collapsing duplicates). Re-run until clean.

- [ ] **Step 6: Verify both suites green**

Run: `cd packages/amuwak_core && flutter test && cd ../..`
Expected: moved theme + enum tests PASS.

Run: `flutter test` (staff app)
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add -A packages/amuwak_core lib test
git commit -m "refactor: move design-system tokens + order_status/service_type enums to amuwak_core"
```

---

### Task 5: Extract motion + generic widgets

**Files:**
- Move: `lib/src/shared/motion/{count_up_text,pressable_scale,reveal_on_mount,animated_gradient_header}.dart` → `packages/amuwak_core/lib/src/shared/motion/`
- Move: `lib/src/shared/widgets/{empty_state,app_theme}.dart` → `packages/amuwak_core/lib/src/shared/widgets/`
- Move tests: `test/shared/motion/*_test.dart`, `test/shared/widgets/{empty_state,app_theme}_test.dart`
- Modify: barrel; staff imports.

> `lib/src/shared/widgets/sync_status_banner.dart` STAYS in the staff app (sync-state coupled). `app_theme.dart` (`buildAmuwakTheme`) depends on the theme tokens moved in Task 4 and on `app_card`/motion — all now in-package.

**Interfaces:**
- Produces (via barrel): `CountUpText`, `PressableScale`, `RevealOnMount`, `AnimatedGradientHeader`, `EmptyState`, and `buildAmuwakTheme()`.

- [ ] **Step 1: Move motion + widget sources**

```bash
git mv lib/src/shared/motion/count_up_text.dart            packages/amuwak_core/lib/src/shared/motion/count_up_text.dart
git mv lib/src/shared/motion/pressable_scale.dart          packages/amuwak_core/lib/src/shared/motion/pressable_scale.dart
git mv lib/src/shared/motion/reveal_on_mount.dart          packages/amuwak_core/lib/src/shared/motion/reveal_on_mount.dart
git mv lib/src/shared/motion/animated_gradient_header.dart packages/amuwak_core/lib/src/shared/motion/animated_gradient_header.dart
git mv lib/src/shared/widgets/empty_state.dart             packages/amuwak_core/lib/src/shared/widgets/empty_state.dart
git mv lib/src/shared/widgets/app_theme.dart               packages/amuwak_core/lib/src/shared/widgets/app_theme.dart
```

- [ ] **Step 2: Add barrel exports**

Append to the barrel:

```dart
export 'src/shared/motion/count_up_text.dart';
export 'src/shared/motion/pressable_scale.dart';
export 'src/shared/motion/reveal_on_mount.dart';
export 'src/shared/motion/animated_gradient_header.dart';
export 'src/shared/widgets/empty_state.dart';
export 'src/shared/widgets/app_theme.dart';
```

- [ ] **Step 3: Fix in-package imports**

Run: `cd packages/amuwak_core && flutter analyze`
Expected: FAIL only if a moved file references a still-in-staff file. `app_theme.dart` should reference only Task-4 tokens + Task-5 widgets (all in-package). Fix any remaining relative-import paths so they resolve within `amuwak_core`; re-run until clean.

- [ ] **Step 4: Move the tests and repoint imports**

```bash
git mv test/shared/motion/count_up_text_test.dart            packages/amuwak_core/test/shared/motion/count_up_text_test.dart
git mv test/shared/motion/pressable_scale_test.dart          packages/amuwak_core/test/shared/motion/pressable_scale_test.dart
git mv test/shared/motion/reveal_on_mount_test.dart          packages/amuwak_core/test/shared/motion/reveal_on_mount_test.dart
git mv test/shared/motion/animated_gradient_header_test.dart packages/amuwak_core/test/shared/motion/animated_gradient_header_test.dart
git mv test/shared/widgets/empty_state_test.dart             packages/amuwak_core/test/shared/widgets/empty_state_test.dart
git mv test/shared/widgets/app_theme_test.dart               packages/amuwak_core/test/shared/widgets/app_theme_test.dart
```

In each, replace imports of moved symbols with `import 'package:amuwak_core/amuwak_core.dart';`.

- [ ] **Step 5: Rewrite staff imports + verify green**

Run: `flutter analyze` (staff) → fix flagged staff files to import `package:amuwak_core/amuwak_core.dart`; repeat until clean.

Run: `cd packages/amuwak_core && flutter test && cd ../..`
Expected: PASS.

Run: `flutter test` (staff)
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add -A packages/amuwak_core lib test
git commit -m "refactor: move motion library + generic widgets (EmptyState, buildAmuwakTheme) to amuwak_core"
```

---

### Task 6: Extract pricing logic

**Files:**
- Move: `lib/src/orders/pricing/{pricing_calculator,pricing_inputs,line_item}.dart` → `packages/amuwak_core/lib/src/orders/pricing/`
- Move tests: `test/orders/pricing/*_test.dart` (the pure-logic tests, e.g. `pricing_calculator_test.dart`)
- Modify: barrel; staff imports.

> `lib/src/orders/pricing/pricing_section.dart` is a **staff widget** — it STAYS in the staff app and will import the moved logic via the barrel.

**Interfaces:**
- Produces (via barrel): `recomputeTotal(PricingInputs) → OrderTotal`, the `PricingInputs` and `OrderTotal` types, and `LineItem` (with `toJson`/`fromJson`).

- [ ] **Step 1: Move the pricing-logic sources**

```bash
git mv lib/src/orders/pricing/pricing_calculator.dart packages/amuwak_core/lib/src/orders/pricing/pricing_calculator.dart
git mv lib/src/orders/pricing/pricing_inputs.dart      packages/amuwak_core/lib/src/orders/pricing/pricing_inputs.dart
git mv lib/src/orders/pricing/line_item.dart           packages/amuwak_core/lib/src/orders/pricing/line_item.dart
```

- [ ] **Step 2: Add barrel exports**

Append to the barrel:

```dart
export 'src/orders/pricing/pricing_calculator.dart';
export 'src/orders/pricing/pricing_inputs.dart';
export 'src/orders/pricing/line_item.dart';
```

- [ ] **Step 3: Move the pure pricing tests**

```bash
git mv test/orders/pricing/pricing_calculator_test.dart packages/amuwak_core/test/orders/pricing/pricing_calculator_test.dart
```

(If `pricing_inputs_test.dart` / `line_item_test.dart` exist, move them the same way.) In each moved test, replace the symbol import with `import 'package:amuwak_core/amuwak_core.dart';`.

- [ ] **Step 4: Verify in-package, then rewrite staff imports**

Run: `cd packages/amuwak_core && flutter analyze && flutter test && cd ../..`
Expected: analyze clean; moved pricing tests PASS.

Run: `flutter analyze` (staff) — fix flagged staff files (notably `lib/src/orders/pricing/pricing_section.dart`, `lib/src/orders/order_details_screen.dart`, `lib/src/orders/new_pickup_screen.dart`, `lib/src/sync/orders_repository.dart`) to import `package:amuwak_core/amuwak_core.dart`. Repeat until clean.

Run: `flutter test` (staff)
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A packages/amuwak_core lib test
git commit -m "refactor: move pricing calculator/inputs/line-item logic to amuwak_core"
```

---

### Task 7: Extract auth + bootstrap

**Files:**
- Move: `lib/src/auth/auth_service.dart`, `lib/src/auth/session.dart` → `packages/amuwak_core/lib/src/auth/`
- Move: `lib/src/bootstrap/app_config.dart`, `lib/src/bootstrap/app_bootstrap.dart` → `packages/amuwak_core/lib/src/bootstrap/`
- Move tests: `test/auth/*_test.dart` for these two files, `test/bootstrap/*_test.dart` if present
- Modify: barrel; staff imports (incl. `lib/main.dart`, `lib/src/auth/auth_gate.dart`, login/set-password screens).

> Only `auth_service.dart` + `session.dart` move (pure auth plumbing). `auth_gate.dart`, `login_screen.dart`, `set_password_screen.dart` route into the **staff** app, so they STAY and consume the moved providers via the barrel. `app_bootstrap.dart` must not pull in Drift seeding — confirm its current online-only form has the Drift seed commented out (project memory: "Online-only mode"); if it still imports Drift, leave `app_bootstrap.dart` in the staff app and move only `app_config.dart`.

**Interfaces:**
- Consumes: `flutter_riverpod`, `supabase_flutter` (already `amuwak_core` deps).
- Produces (via barrel): `AuthService`, `AuthFailure`, `authServiceProvider`, `authStateProvider`, `currentUserIdProvider`, `currentAuthEventProvider`, `currentRoleProvider`, `roleFromAccessToken`, `AppConfig`, and (if moved) `AppBootstrap`.

- [ ] **Step 1: Check `app_bootstrap.dart` for Drift coupling**

Run: `flutter analyze` is not needed yet — instead read `lib/src/bootstrap/app_bootstrap.dart` and confirm it does not `import` any `drift`/`app_database` symbol in active (non-commented) code.
Expected: online-only form has no active Drift import. If it does, skip moving `app_bootstrap.dart` (move only `app_config.dart`) and adjust Steps 2/4 accordingly.

- [ ] **Step 2: Move the sources**

```bash
git mv lib/src/auth/auth_service.dart      packages/amuwak_core/lib/src/auth/auth_service.dart
git mv lib/src/auth/session.dart           packages/amuwak_core/lib/src/auth/session.dart
git mv lib/src/bootstrap/app_config.dart   packages/amuwak_core/lib/src/bootstrap/app_config.dart
git mv lib/src/bootstrap/app_bootstrap.dart packages/amuwak_core/lib/src/bootstrap/app_bootstrap.dart
```

(Omit the last line if Step 1 found Drift coupling.)

- [ ] **Step 3: Add barrel exports**

Append to the barrel:

```dart
export 'src/auth/auth_service.dart';
export 'src/auth/session.dart';
export 'src/bootstrap/app_config.dart';
export 'src/bootstrap/app_bootstrap.dart';
```

(Omit the `app_bootstrap.dart` line if it stayed in the staff app.) Note `session.dart` imports `auth_service.dart` via a relative `import 'auth_service.dart';` — that still resolves after the co-located move, no change needed.

- [ ] **Step 4: Move the auth/bootstrap tests**

Move the auth tests covering these files (e.g. `test/auth/auth_service_test.dart`, `test/auth/session_test.dart`) and any `test/bootstrap/app_config_test.dart`:

```bash
git mv test/auth/auth_service_test.dart packages/amuwak_core/test/auth/auth_service_test.dart
git mv test/auth/session_test.dart      packages/amuwak_core/test/auth/session_test.dart
```

In each, replace the symbol imports with `import 'package:amuwak_core/amuwak_core.dart';`. (Leave tests for `auth_gate`/`login_screen`/`set_password_screen` in the staff app — those widgets did not move.)

- [ ] **Step 5: Verify in-package, then rewrite staff imports**

Run: `cd packages/amuwak_core && flutter analyze && flutter test && cd ../..`
Expected: analyze clean; moved auth/bootstrap tests PASS.

Run: `flutter analyze` (staff) — fix flagged files, importantly `lib/main.dart`, `lib/src/auth/auth_gate.dart`, `lib/src/auth/login_screen.dart`, `lib/src/auth/set_password_screen.dart`, and any screen reading `currentRoleProvider`/`currentUserIdProvider` — to import `package:amuwak_core/amuwak_core.dart`. Repeat until clean.

Run: `flutter test` (staff)
Expected: PASS (including the staff `auth_gate`/login/set-password widget tests, now importing providers from the barrel).

- [ ] **Step 6: Commit**

```bash
git add -A packages/amuwak_core lib test
git commit -m "refactor: move AuthService, session providers, and bootstrap/config to amuwak_core"
```

---

## Self-Review notes (verification of this plan)

- **Spec coverage:** Phase A of the approved design = monorepo + extract the pure/app-agnostic layer + CI test job. Tasks 1–2 cover the workspace/Melos/CI; Tasks 3–7 cover utilities, design system, motion/widgets, pricing logic, domain enums, auth, bootstrap. The Drift-free model split + repository extraction + `OrderMessagesRepository` are explicitly deferred (see "Out of scope") because they need Plan 2's table and are higher-risk — they are first-class tasks in the customer-app plan.
- **No behavior change:** every task is verified by the pre-existing (moved) test suite plus `flutter analyze`; the staff app must stay green at each commit.
- **Ordering hazard handled:** `status_colors.dart` → `OrderStatus` forward dependency is resolved by moving the two pure enums during Task 4.
- **Host constraint honored:** all test commands are whole-package or single-file; Melos `test` runs with `concurrency: 1`.

## Final verification (end of Phase A)
- Run `dart run melos run analyze` → clean across `amuwak_staff` + `amuwak_core`.
- Run `dart run melos run test` → both packages green.
- Build the staff app once to confirm asset/font wiring is intact: `flutter build web --release --dart-define SUPABASE_URL=$URL --dart-define SUPABASE_ANON_KEY=$KEY` → succeeds.
- Confirm `amuwak_core` has **no** Drift import: `grep -rE "drift|app_database" packages/amuwak_core/lib` → no matches.
- Confirm the dependency direction: `grep -r "package:amuwak_staff" packages/amuwak_core` → no matches.
