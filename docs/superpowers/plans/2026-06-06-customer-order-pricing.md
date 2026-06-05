# Customer Order Pricing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bill Amuwak laundry orders on `weight × rate` plus free-form line items and a manual adjustment, with a global default rate, optional per-customer override, a frozen per-order rate snapshot, and two-step weight capture (estimate at pickup, final at intake).

**Architecture:** A pure, dependency-free pricing module (`recomputeTotal`, `LineItem`, `PricingInputs`) is the single source of truth for the math. The stored `orders.total_ugx` is always recomputed from its inputs at the repository write chokepoint, never trusted from the caller. Currency rates/weights are `numeric` in Postgres (sub-shilling rate precision) and `double` in Dart; line-item amounts, the manual adjustment, and the order total are integer UGX end-to-end. A singleton `pricing_settings` row holds the global default; a per-customer override column shadows it; the resolved rate is frozen into the order at creation.

**Tech Stack:** Flutter, Riverpod, Supabase (Postgres + realtime), Drift (offline path, currently dormant but kept compiling), pgTAP for SQL tests, `flutter_test` for Dart/widget tests.

---

## Pre-flight: integration decisions

These three points reconcile the design spec (`docs/superpowers/specs/2026-06-05-customer-order-pricing-design.md`) with the **actual** state of the codebase. Read them before starting — they change two spec items.

1. **No standalone `IntakeScreen` (spec §5.4).** The spec describes a new `IntakeScreen` that runs the `pending_pickup → received` transition. But the existing `PickupCaptureScreen._onDone()` (`lib/src/orders/proof/pickup_capture_screen.dart:186-193`) **already** transitions `pending_pickup → in_progress` (`received` folds into `inProgress` in the 4-status UI — see `OrderStatus.fromDbString`). Adding a second screen that owns the same transition would create two conflicting "intake" paths. **Decision:** capture the *estimate* in `PickupCaptureScreen` (Task 16) and capture the *final weight* in the editable Pricing block on `OrderDetailsScreen` (Task 17). The spec's IntakeScreen goal — record final weight, recompute total — is fully met by Task 17 without a new screen or status. This is a deliberate deviation; revisit if a distinct shop-intake role/status is added later.

2. **No customer-edit screen exists (spec §5.4 "Customer edit screen").** Customers are only ever created inside `NewPickupScreen`; there is no edit screen anywhere in `lib/`. **Decision:** ship the `customers.custom_rate_per_kg_ugx` column, its mapper/payload wiring, and the new-pickup rate resolution now (so an override set via back-office/SQL already takes effect everywhere). Add the *editing UI* as the last task (Task 19) by extending `NewPickupScreen`'s optional-details section, which is the only customer-write surface that exists. A dedicated edit screen is out of scope for v1.

3. **No `pricing_settings` UI host exists, but the Account tab does.** The dashboard already renders an `_AccountTab` (`lib/src/dashboard/staff_dashboard_screen.dart:575`). Task 18 adds a "Pricing settings" row there that pushes a new `PricingSettingsScreen`. No new navigation framework needed.

**Currency types recap (do not deviate):**
- `rate_per_kg` / `*_weight_kg` → Postgres `numeric`, Dart `double`.
- `line_items[].amount_ugx`, `manual_adjustment_ugx`, `total_ugx` → Postgres `integer`, Dart `int`.
- All money shown to staff goes through `formatUgx(int)` (Task 5): `USh 8,000`.

---

## File structure

**Created:**
- `supabase/migrations/0019_order_pricing.sql` — schema: customer override column, order pricing columns, `pricing_settings` table + seed + backfill.
- `supabase/tests/0019_order_pricing_test.sql` — pgTAP coverage of the above.
- `lib/src/orders/pricing/line_item.dart` — `LineItem` value type + validation + JSON.
- `lib/src/orders/pricing/pricing_inputs.dart` — `PricingInputs` + `OrderTotal` value types.
- `lib/src/orders/pricing/pricing_calculator.dart` — pure `recomputeTotal(...)`.
- `lib/src/shared/format_ugx.dart` — `formatUgx(int)` display helper.
- `lib/src/data/tables/pricing_settings_table.dart` — Drift table mirroring `pricing_settings`.
- `lib/src/pricing/pricing_settings.dart` — `PricingSettings` domain model + JSON.
- `lib/src/pricing/pricing_settings_repository.dart` — read/write the singleton row.
- `lib/src/pricing/pricing_providers.dart` — `pricingSettingsRepositoryProvider`, `defaultRatePerKgUgxProvider`.
- `lib/src/orders/pricing/pricing_section.dart` — shared editable Pricing widgets (line-item editor, total card) reused by pickup + details.
- Test files mirroring each of the above under `test/`.

**Modified:**
- `lib/src/data/tables/orders_table.dart` — six pricing columns.
- `lib/src/data/tables/customers_table.dart` — `customRatePerKgUgx` column.
- `lib/src/data/app_database.dart` — register `PricingSettings`, bump `schemaVersion` 2→3, add `onUpgrade`.
- `lib/src/orders/order.dart` — six pricing fields across `fromDriftRow`/`fromSupabase`/`copyWith`/`==`/`hashCode`.
- `lib/src/sync/supabase_mappers.dart` — read customer custom rate; pricing settings mapper.
- `lib/src/sync/supabase_payloads.dart` — order payload writes pricing; customer payload writes override.
- `lib/src/sync/orders_repository.dart` — recompute total on every write; resolve+freeze rate on create.
- `lib/src/sync/repository_providers.dart` — nothing structural; pricing providers live in their own file.
- `lib/src/orders/new_pickup_screen.dart` — resolved-rate display + custom-rate field (Tasks 15, 19).
- `lib/src/orders/proof/pickup_capture_screen.dart` — estimate + line items + provisional total (Task 16).
- `lib/src/orders/order_details_screen.dart` — editable Pricing block w/ final weight (Task 17).
- `lib/src/dashboard/staff_dashboard_screen.dart` — Account-tab "Pricing settings" entry (Task 18).

---

## Phase 1 — Database

### Task 1: Migration `0019_order_pricing.sql`

**Files:**
- Create: `supabase/migrations/0019_order_pricing.sql`

- [ ] **Step 1: Write the migration**

```sql
-- 0019_order_pricing.sql
-- Adds weight × rate pricing to orders: a per-customer rate override, a frozen
-- per-order rate snapshot, two-step weights (estimate/final), free-form line
-- items, a manual adjustment, and a computed integer total. Plus a singleton
-- pricing_settings table holding the global default rate.
--
-- Money columns: rates/weights are numeric (sub-shilling precision for rates,
-- 2dp for kg); line-item amounts, manual adjustment, and total_ugx are integer
-- UGX. See docs/superpowers/specs/2026-06-05-customer-order-pricing-design.md.

-- 4.1 Per-customer override. NULL = use the global default.
ALTER TABLE customers
  ADD COLUMN custom_rate_per_kg_ugx numeric(10,2)
    CHECK (custom_rate_per_kg_ugx IS NULL OR custom_rate_per_kg_ugx > 0);

-- 4.2 Order pricing columns. DEFAULT 0 on the snapshot is for the backfill only;
-- the Dart layer always supplies a real value on insert.
ALTER TABLE orders
  ADD COLUMN rate_per_kg_snapshot_ugx numeric(10,2) NOT NULL DEFAULT 0
    CHECK (rate_per_kg_snapshot_ugx >= 0),
  ADD COLUMN estimated_weight_kg numeric(6,2)
    CHECK (estimated_weight_kg IS NULL OR estimated_weight_kg >= 0),
  ADD COLUMN final_weight_kg numeric(6,2)
    CHECK (final_weight_kg IS NULL OR final_weight_kg >= 0),
  ADD COLUMN line_items jsonb NOT NULL DEFAULT '[]'::jsonb
    CHECK (jsonb_typeof(line_items) = 'array'),
  ADD COLUMN manual_adjustment_ugx integer NOT NULL DEFAULT 0,
  ADD COLUMN total_ugx integer NOT NULL DEFAULT 0
    CHECK (total_ugx >= 0);

-- 4.3 Singleton settings table. No deleted_at by design: a deleted settings row
-- would leave the app with no rate to resolve.
CREATE TABLE pricing_settings (
  id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  default_rate_per_kg_ugx numeric(10,2) NOT NULL CHECK (default_rate_per_kg_ugx > 0),
  updated_at              timestamptz NOT NULL DEFAULT now(),
  updated_by              uuid REFERENCES staff(id)
);

-- Enforce exactly one row.
CREATE UNIQUE INDEX pricing_settings_singleton ON pricing_settings ((true));

-- Seed a placeholder default; update via the in-app settings screen after deploy.
INSERT INTO pricing_settings (default_rate_per_kg_ugx) VALUES (5000.00);

-- Backfill existing orders with the seeded default so they have a non-zero
-- snapshot to display. Weights stay NULL and total_ugx stays 0 until staff
-- record them.
UPDATE orders
  SET rate_per_kg_snapshot_ugx = (SELECT default_rate_per_kg_ugx FROM pricing_settings)
  WHERE rate_per_kg_snapshot_ugx = 0;

-- RLS: authenticated staff may read and update pricing_settings (no role gate in
-- v1, per spec §2/§9). Mirror the orders/customers grant pattern.
ALTER TABLE pricing_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY pricing_settings_select ON pricing_settings
  FOR SELECT TO authenticated USING (true);
CREATE POLICY pricing_settings_update ON pricing_settings
  FOR UPDATE TO authenticated USING (true) WITH CHECK (true);
```

> Note for the implementer: confirm the existing RLS convention in `0007_rls.sql` / `0010_tighten_orders_rls.sql` before finalizing the two policies — match whatever role/`USING` shape those use. The columns and the singleton index are the load-bearing parts; the policy wording is the one place to align with house style.

- [ ] **Step 2: Add `pricing_settings` to the realtime publication note**

The settings screen reads via a one-shot select, not a stream, so realtime is **not** required for `pricing_settings`. No change to the `alter publication supabase_realtime ...` ops list. Add this comment at the bottom of the migration so the next person doesn't add it reflexively:

```sql
-- NB: pricing_settings is intentionally NOT added to supabase_realtime. The
-- settings screen reads it one-shot; orders carry their own frozen snapshot.
```

- [ ] **Step 3: Apply locally and verify it loads**

Run: `supabase db reset` (or the project's migration-apply command — check `supabase/README.md`).
Expected: all migrations through `0019` apply with no error; `\d orders` shows the six new columns and `\d pricing_settings` shows the table.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/0019_order_pricing.sql
git commit -m "feat(db): add order pricing columns and pricing_settings table"
```

### Task 2: SQL test `0019_order_pricing_test.sql`

**Files:**
- Create: `supabase/tests/0019_order_pricing_test.sql`

- [ ] **Step 1: Write the pgTAP test**

```sql
-- 0019_order_pricing_test.sql
-- Verifies the pricing schema: new columns exist, CHECK constraints reject bad
-- values, the pricing_settings singleton is enforced and seeded, and the
-- backfill set a non-zero snapshot on pre-existing orders.
-- Runs inside BEGIN ... ROLLBACK so nothing touches real data.

BEGIN;
SET search_path TO extensions, public;

SELECT plan(11);

-- Columns exist.
SELECT has_column('customers', 'custom_rate_per_kg_ugx');
SELECT has_column('orders', 'rate_per_kg_snapshot_ugx');
SELECT has_column('orders', 'estimated_weight_kg');
SELECT has_column('orders', 'final_weight_kg');
SELECT has_column('orders', 'line_items');
SELECT has_column('orders', 'total_ugx');
SELECT has_table('pricing_settings');

-- Seeded default is present and positive.
SELECT ok(
  (SELECT default_rate_per_kg_ugx FROM pricing_settings) > 0,
  'pricing_settings seeded with a positive default rate');

-- Singleton: a second insert violates the unique index.
SELECT throws_ok(
  $$INSERT INTO pricing_settings (default_rate_per_kg_ugx) VALUES (6000.00)$$,
  '23505', NULL,
  'pricing_settings rejects a second row (singleton)');

-- CHECK: negative custom rate rejected.
SELECT throws_ok(
  $$UPDATE customers SET custom_rate_per_kg_ugx = -1
      WHERE id = (SELECT id FROM customers LIMIT 1)$$,
  '23514', NULL,
  'customers.custom_rate_per_kg_ugx rejects a negative value');

-- CHECK: non-array line_items rejected.
SELECT throws_ok(
  $$UPDATE orders SET line_items = '{}'::jsonb
      WHERE id = (SELECT id FROM orders LIMIT 1)$$,
  '23514', NULL,
  'orders.line_items rejects a non-array jsonb');

SELECT * FROM finish();
ROLLBACK;
```

> If the DB has no seed customers/orders in the test environment, the two `UPDATE ... WHERE id = (SELECT ... LIMIT 1)` cases become no-ops and the `throws_ok` will fail. In that case, insert a throwaway customer/order at the top of the transaction first (mirror the setup in `0003_orders_and_transitions_test.sql`). Adjust `plan(N)` if you add assertions.

- [ ] **Step 2: Run the test**

Run: the project's pgTAP runner (check `supabase/README.md`; typically `supabase test db` or a `pg_prove` invocation).
Expected: all assertions pass.

- [ ] **Step 3: Commit**

```bash
git add supabase/tests/0019_order_pricing_test.sql
git commit -m "test(db): pgTAP coverage for order pricing schema"
```

---

## Phase 2 — Pure pricing module (no Flutter, no Supabase)

### Task 3: `LineItem` value type

**Files:**
- Create: `lib/src/orders/pricing/line_item.dart`
- Test: `test/orders/pricing/line_item_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:amuwak_staff/src/orders/pricing/line_item.dart';

void main() {
  group('LineItem', () {
    test('constructs with a trimmed name and non-negative amount', () {
      final item = LineItem(name: '  Blanket ', amountUgx: 8000);
      expect(item.name, 'Blanket');
      expect(item.amountUgx, 8000);
    });

    test('rejects an empty or whitespace-only name', () {
      expect(() => LineItem(name: '', amountUgx: 1000), throwsArgumentError);
      expect(() => LineItem(name: '   ', amountUgx: 1000), throwsArgumentError);
    });

    test('rejects a negative amount', () {
      expect(() => LineItem(name: 'Jacket', amountUgx: -1), throwsArgumentError);
    });

    test('round-trips through JSON', () {
      final item = LineItem(name: 'Jacket', amountUgx: 5000);
      expect(LineItem.fromJson(item.toJson()), item);
    });

    test('fromJson reads a Supabase jsonb map', () {
      final item = LineItem.fromJson({'name': 'Duvet', 'amount_ugx': 12000});
      expect(item.name, 'Duvet');
      expect(item.amountUgx, 12000);
    });

    test('value equality', () {
      expect(
        LineItem(name: 'A', amountUgx: 100),
        LineItem(name: 'A', amountUgx: 100),
      );
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/orders/pricing/line_item_test.dart`
Expected: FAIL — `line_item.dart` does not exist.

- [ ] **Step 3: Implement `LineItem`**

```dart
/// A free-form charge for a special piece (blanket, jacket, duvet…) on an order.
/// `name` is trimmed and must be non-empty; `amountUgx` is integer UGX >= 0.
/// Discounts do NOT go here — they go through the order's manual adjustment.
class LineItem {
  LineItem({required String name, required this.amountUgx})
      : name = name.trim() {
    if (this.name.isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be empty');
    }
    if (amountUgx < 0) {
      throw ArgumentError.value(amountUgx, 'amountUgx', 'must be >= 0');
    }
  }

  final String name;
  final int amountUgx;

  /// Serializes to the snake_case shape stored in `orders.line_items` (jsonb).
  Map<String, dynamic> toJson() => {'name': name, 'amount_ugx': amountUgx};

  /// Reads either a freshly-decoded jsonb map (Supabase) or a `toJson` map.
  factory LineItem.fromJson(Map<String, dynamic> json) => LineItem(
        name: json['name'] as String,
        amountUgx: (json['amount_ugx'] as num).toInt(),
      );

  @override
  bool operator ==(Object other) =>
      other is LineItem && other.name == name && other.amountUgx == amountUgx;

  @override
  int get hashCode => Object.hash(name, amountUgx);

  @override
  String toString() => 'LineItem($name, $amountUgx)';
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/orders/pricing/line_item_test.dart`
Expected: PASS (all 6 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/src/orders/pricing/line_item.dart test/orders/pricing/line_item_test.dart
git commit -m "feat(pricing): add LineItem value type with validation and JSON"
```

### Task 4: `PricingInputs`, `OrderTotal`, and `recomputeTotal`

**Files:**
- Create: `lib/src/orders/pricing/pricing_inputs.dart`
- Create: `lib/src/orders/pricing/pricing_calculator.dart`
- Test: `test/orders/pricing/pricing_calculator_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:amuwak_staff/src/orders/pricing/line_item.dart';
import 'package:amuwak_staff/src/orders/pricing/pricing_inputs.dart';
import 'package:amuwak_staff/src/orders/pricing/pricing_calculator.dart';

void main() {
  group('recomputeTotal', () {
    test('zero weight and no line items yields zero, provisional', () {
      final t = recomputeTotal(PricingInputs(ratePerKgUgx: 5000));
      expect(t.weightCharge, 0);
      expect(t.lineItemsSum, 0);
      expect(t.total, 0);
      expect(t.isProvisional, isTrue);
    });

    test('bills on final weight when present (not provisional)', () {
      final t = recomputeTotal(PricingInputs(
        ratePerKgUgx: 5000,
        estimatedWeightKg: 3,
        finalWeightKg: 4,
      ));
      expect(t.weightCharge, 20000); // 4 * 5000
      expect(t.isProvisional, isFalse);
    });

    test('falls back to estimate when no final weight (provisional)', () {
      final t = recomputeTotal(PricingInputs(
        ratePerKgUgx: 5000,
        estimatedWeightKg: 3,
      ));
      expect(t.weightCharge, 15000); // 3 * 5000
      expect(t.isProvisional, isTrue);
    });

    test('rounds the weight charge half-up, once', () {
      // 2.5kg * 3333 = 8332.5 -> 8333
      final t = recomputeTotal(
          PricingInputs(ratePerKgUgx: 3333, finalWeightKg: 2.5));
      expect(t.weightCharge, 8333);
    });

    test('adds line items to the weight charge', () {
      final t = recomputeTotal(PricingInputs(
        ratePerKgUgx: 5000,
        finalWeightKg: 2,
        lineItems: [
          LineItem(name: 'Blanket', amountUgx: 8000),
          LineItem(name: 'Jacket', amountUgx: 5000),
        ],
      ));
      expect(t.lineItemsSum, 13000);
      expect(t.total, 23000); // 10000 + 13000
    });

    test('a negative manual adjustment reduces the total', () {
      final t = recomputeTotal(PricingInputs(
        ratePerKgUgx: 5000,
        finalWeightKg: 4,
        manualAdjustmentUgx: -5000,
      ));
      expect(t.total, 15000); // 20000 - 5000
    });

    test('total is clamped at 0 when the adjustment overshoots', () {
      final t = recomputeTotal(PricingInputs(
        ratePerKgUgx: 5000,
        finalWeightKg: 1,
        manualAdjustmentUgx: -999999,
      ));
      expect(t.total, 0);
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/orders/pricing/pricing_calculator_test.dart`
Expected: FAIL — files do not exist.

- [ ] **Step 3: Implement `PricingInputs` + `OrderTotal`**

`lib/src/orders/pricing/pricing_inputs.dart`:

```dart
import 'line_item.dart';

/// Immutable bundle of everything `recomputeTotal` needs. Pure data — no I/O.
class PricingInputs {
  const PricingInputs({
    required this.ratePerKgUgx,
    this.estimatedWeightKg,
    this.finalWeightKg,
    this.lineItems = const [],
    this.manualAdjustmentUgx = 0,
  });

  final double ratePerKgUgx;
  final double? estimatedWeightKg;
  final double? finalWeightKg;
  final List<LineItem> lineItems;
  final int manualAdjustmentUgx;
}

/// Result of `recomputeTotal`: the breakdown plus the clamped total and whether
/// the order is still billing on an estimate.
class OrderTotal {
  const OrderTotal({
    required this.weightCharge,
    required this.lineItemsSum,
    required this.total,
    required this.isProvisional,
  });

  final int weightCharge;
  final int lineItemsSum;
  final int total;
  final bool isProvisional;
}
```

- [ ] **Step 4: Implement `recomputeTotal`**

`lib/src/orders/pricing/pricing_calculator.dart`:

```dart
import 'pricing_inputs.dart';

/// The single source of truth for an order's total. Pure, deterministic, no I/O.
///
/// weight_to_bill   = final ?? estimate ?? 0
/// weight_charge    = round_half_up(weight_to_bill * rate)   (once, not per line)
/// line_items_sum   = Σ line item amounts
/// total            = max(0, weight_charge + line_items_sum + manual_adjustment)
///
/// Rounding is half-up (matches a phone calculator the rider might run), not
/// banker's rounding. The order is provisional until a final weight is set.
OrderTotal recomputeTotal(PricingInputs inputs) {
  final weightToBill =
      inputs.finalWeightKg ?? inputs.estimatedWeightKg ?? 0;
  final weightCharge = _roundHalfUp(weightToBill * inputs.ratePerKgUgx);
  final lineItemsSum =
      inputs.lineItems.fold<int>(0, (sum, item) => sum + item.amountUgx);
  final raw = weightCharge + lineItemsSum + inputs.manualAdjustmentUgx;
  return OrderTotal(
    weightCharge: weightCharge,
    lineItemsSum: lineItemsSum,
    total: raw < 0 ? 0 : raw,
    isProvisional: inputs.finalWeightKg == null,
  );
}

/// Half-up rounding for non-negative values: (x + 0.5).floor().
int _roundHalfUp(double x) => (x + 0.5).floor();
```

- [ ] **Step 5: Run to verify it passes**

Run: `flutter test test/orders/pricing/pricing_calculator_test.dart`
Expected: PASS (all 7 tests).

- [ ] **Step 6: Commit**

```bash
git add lib/src/orders/pricing/pricing_inputs.dart lib/src/orders/pricing/pricing_calculator.dart test/orders/pricing/pricing_calculator_test.dart
git commit -m "feat(pricing): add PricingInputs, OrderTotal, and recomputeTotal"
```

### Task 5: `formatUgx` display helper

**Files:**
- Create: `lib/src/shared/format_ugx.dart`
- Test: `test/shared/format_ugx_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:amuwak_staff/src/shared/format_ugx.dart';

void main() {
  group('formatUgx', () {
    test('adds thousands separators and the USh prefix', () {
      expect(formatUgx(8000), 'USh 8,000');
      expect(formatUgx(1500000), 'USh 1,500,000');
    });

    test('handles values below 1000 with no separator', () {
      expect(formatUgx(0), 'USh 0');
      expect(formatUgx(500), 'USh 500');
    });

    test('formats negative values (e.g. a discount preview)', () {
      expect(formatUgx(-5000), 'USh -5,000');
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/shared/format_ugx_test.dart`
Expected: FAIL — file does not exist.

- [ ] **Step 3: Implement `formatUgx`**

```dart
/// Formats an integer UGX amount for display: `USh 8,000`. No decimal places
/// (UGX has no practical subdivision). Negative values keep the sign after the
/// prefix: `USh -5,000`. Single source of truth for money rendering — every
/// screen uses this so separators and the prefix never drift.
String formatUgx(int amountUgx) {
  final negative = amountUgx < 0;
  final digits = amountUgx.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i != 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return 'USh ${negative ? '-' : ''}$buffer';
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/shared/format_ugx_test.dart`
Expected: PASS (all 3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/src/shared/format_ugx.dart test/shared/format_ugx_test.dart
git commit -m "feat(shared): add formatUgx money display helper"
```

---

## Phase 3 — Persistence layer (Drift + domain models)

### Task 6: Drift columns + `pricing_settings` table + schema bump

**Files:**
- Modify: `lib/src/data/tables/orders_table.dart`
- Modify: `lib/src/data/tables/customers_table.dart`
- Create: `lib/src/data/tables/pricing_settings_table.dart`
- Modify: `lib/src/data/app_database.dart:19-40`
- Test: `test/app_database_test.dart` (extend)

> Context: the Drift/offline path is dormant in online-only mode, but `LaundryOrder.fromDriftRow` still references these columns and the project still runs `build_runner`. Keeping Drift in sync keeps the app compiling and the offline path re-enableable.

- [ ] **Step 1: Add the order columns**

In `lib/src/data/tables/orders_table.dart`, after the `deletedAt` column and before `@override Set<Column> get primaryKey`:

```dart
  RealColumn     get ratePerKgSnapshotUgx => real().named('rate_per_kg_snapshot_ugx').withDefault(const Constant(0))();
  RealColumn     get estimatedWeightKg    => real().named('estimated_weight_kg').nullable()();
  RealColumn     get finalWeightKg        => real().named('final_weight_kg').nullable()();
  TextColumn     get lineItems            => text().named('line_items').withDefault(const Constant('[]'))();
  IntColumn      get manualAdjustmentUgx  => integer().named('manual_adjustment_ugx').withDefault(const Constant(0))();
  IntColumn      get totalUgx             => integer().named('total_ugx').withDefault(const Constant(0))();
```

- [ ] **Step 2: Add the customer column**

In `lib/src/data/tables/customers_table.dart`, after `notes` and before `createdAt`:

```dart
  RealColumn get customRatePerKgUgx => real().named('custom_rate_per_kg_ugx').nullable()();
```

- [ ] **Step 3: Create the `PricingSettings` Drift table**

`lib/src/data/tables/pricing_settings_table.dart`:

```dart
import 'package:drift/drift.dart';

class PricingSettings extends Table {
  TextColumn     get id                   => text()();
  RealColumn     get defaultRatePerKgUgx  => real().named('default_rate_per_kg_ugx')();
  DateTimeColumn get updatedAt            => dateTime().named('updated_at')();
  TextColumn     get updatedBy            => text().named('updated_by').nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
```

- [ ] **Step 4: Register the table and bump the schema**

In `lib/src/data/app_database.dart`, add the import and table, then bump version + migration:

```dart
import 'tables/pricing_settings_table.dart';
```

Add `PricingSettings` to the `@DriftDatabase(tables: [...])` list. Then:

```dart
  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(pullDeadLetter);
          }
          if (from < 3) {
            await m.addColumn(orders, orders.ratePerKgSnapshotUgx);
            await m.addColumn(orders, orders.estimatedWeightKg);
            await m.addColumn(orders, orders.finalWeightKg);
            await m.addColumn(orders, orders.lineItems);
            await m.addColumn(orders, orders.manualAdjustmentUgx);
            await m.addColumn(orders, orders.totalUgx);
            await m.addColumn(customers, customers.customRatePerKgUgx);
            await m.createTable(pricingSettings);
          }
        },
      );
```

- [ ] **Step 5: Regenerate Drift code**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: `app_database.g.dart` regenerates with the new columns and the `PricingSettings`/`PricingSetting` data classes, no errors.

- [ ] **Step 6: Write a migration test**

Add to `test/app_database_test.dart`:

```dart
  test('schemaVersion is 3', () {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    expect(db.schemaVersion, 3);
  });

  test('orders table exposes the pricing columns', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    // createAll() runs onCreate; a select compiling proves the columns exist.
    final rows = await db.select(db.orders).get();
    expect(rows, isEmpty);
  });
```

> Match the existing imports/setup in `test/app_database_test.dart` (it already constructs `AppDatabase.forTesting`). If `NativeDatabase` isn't imported there, add `import 'package:drift/native.dart';`.

- [ ] **Step 7: Run the tests**

Run: `flutter test test/app_database_test.dart`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add lib/src/data/ test/app_database_test.dart
git commit -m "feat(data): add pricing columns, pricing_settings Drift table, schema v3"
```

### Task 7: `LaundryOrder` pricing fields

**Files:**
- Modify: `lib/src/orders/order.dart`
- Test: `test/orders/order_pricing_test.dart` (new)

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:amuwak_staff/src/orders/line_item_helpers.dart'; // see note below
import 'package:amuwak_staff/src/orders/order.dart';
import 'package:amuwak_staff/src/orders/pricing/line_item.dart';
import 'package:amuwak_staff/src/orders/order_status.dart';
import 'package:amuwak_staff/src/orders/service_type.dart';

LaundryOrder _base() => LaundryOrder(
      orderId: 'o1',
      customerName: 'Aisha',
      serviceType: ServiceType.washAndIron,
      status: OrderStatus.pendingPickup,
      timeLabel: 'Pickup: now',
      itemCount: 0,
      phone: '+256 700000000',
      address: 'Kampala',
      notes: '',
      ratePerKgSnapshotUgx: 5000,
    );

void main() {
  group('LaundryOrder pricing', () {
    test('defaults: no weights, empty line items, zero adjustment/total', () {
      final o = _base();
      expect(o.estimatedWeightKg, isNull);
      expect(o.finalWeightKg, isNull);
      expect(o.lineItems, isEmpty);
      expect(o.manualAdjustmentUgx, 0);
      expect(o.totalUgx, 0);
      expect(o.ratePerKgSnapshotUgx, 5000);
    });

    test('copyWith updates pricing fields and keeps the rest', () {
      final o = _base().copyWith(
        estimatedWeightKg: 3,
        lineItems: [LineItem(name: 'Blanket', amountUgx: 8000)],
        manualAdjustmentUgx: -1000,
        totalUgx: 22000,
      );
      expect(o.estimatedWeightKg, 3);
      expect(o.lineItems.single.name, 'Blanket');
      expect(o.manualAdjustmentUgx, -1000);
      expect(o.totalUgx, 22000);
      expect(o.customerName, 'Aisha');
    });

    test('fromSupabase reads pricing columns including jsonb line_items', () {
      final o = LaundryOrder.fromSupabase({
        'id': 'o2',
        'order_code': 'AMW-2026-0002',
        'customer_id': null,
        'customer_name': 'Bob',
        'phone': '+256 700000001',
        'address': 'Jinja',
        'service_type': 'Wash only',
        'status': 'pending_pickup',
        'item_count': 0,
        'notes': null,
        'scheduled_for': null,
        'rate_per_kg_snapshot_ugx': 5000,
        'estimated_weight_kg': 2.5,
        'final_weight_kg': null,
        'line_items': [
          {'name': 'Jacket', 'amount_ugx': 5000},
        ],
        'manual_adjustment_ugx': 0,
        'total_ugx': 17500,
      }, const []);
      expect(o.ratePerKgSnapshotUgx, 5000);
      expect(o.estimatedWeightKg, 2.5);
      expect(o.finalWeightKg, isNull);
      expect(o.lineItems.single.name, 'Jacket');
      expect(o.totalUgx, 17500);
    });

    test('equality includes pricing fields', () {
      expect(_base().copyWith(totalUgx: 1) == _base(), isFalse);
    });
  });
}
```

> Note: the `line_item_helpers.dart` import in the test is a hint that `fromSupabase` needs a jsonb→`List<LineItem>` parser. Put that parser inline in `order.dart` (Step 3) rather than a separate file; then delete that import line from the test before running. (It's here only to flag the requirement — remove it.)

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/orders/order_pricing_test.dart`
Expected: FAIL — `ratePerKgSnapshotUgx` is not a parameter of `LaundryOrder`.

- [ ] **Step 3: Add the fields to `LaundryOrder`**

In `lib/src/orders/order.dart`:

Add the import at the top:
```dart
import 'pricing/line_item.dart';
```

Add to the constructor parameter list (after `proofEvents`):
```dart
    this.ratePerKgSnapshotUgx = 0,
    this.estimatedWeightKg,
    this.finalWeightKg,
    this.lineItems = const [],
    this.manualAdjustmentUgx = 0,
    this.totalUgx = 0,
```

Add the fields (after `proofEvents`):
```dart
  final double ratePerKgSnapshotUgx;
  final double? estimatedWeightKg;
  final double? finalWeightKg;
  final List<LineItem> lineItems;
  final int manualAdjustmentUgx;
  final int totalUgx;
```

Add a private jsonb parser near `_blankToNull`:
```dart
  /// Parses `orders.line_items` (a jsonb array from Supabase, already decoded to
  /// `List`, or `null`) into typed [LineItem]s. Drops nothing — validation lives
  /// in [LineItem]'s constructor.
  static List<LineItem> _parseLineItems(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .map((e) => LineItem.fromJson((e as Map).cast<String, dynamic>()))
        .toList(growable: false);
  }
```

In `fromDriftRow`, add (note Drift stores `line_items` as a TEXT string, so it must be JSON-decoded — add `import 'dart:convert';` at the top):
```dart
      ratePerKgSnapshotUgx: row.ratePerKgSnapshotUgx,
      estimatedWeightKg: row.estimatedWeightKg,
      finalWeightKg: row.finalWeightKg,
      lineItems: _parseLineItems(jsonDecode(row.lineItems)),
      manualAdjustmentUgx: row.manualAdjustmentUgx,
      totalUgx: row.totalUgx,
```

In `fromSupabase`, add (Supabase decodes jsonb to a `List` directly — no jsonDecode):
```dart
      ratePerKgSnapshotUgx: (row['rate_per_kg_snapshot_ugx'] as num).toDouble(),
      estimatedWeightKg: (row['estimated_weight_kg'] as num?)?.toDouble(),
      finalWeightKg: (row['final_weight_kg'] as num?)?.toDouble(),
      lineItems: _parseLineItems(row['line_items']),
      manualAdjustmentUgx: (row['manual_adjustment_ugx'] as num?)?.toInt() ?? 0,
      totalUgx: (row['total_ugx'] as num?)?.toInt() ?? 0,
```

In `copyWith`, add the parameters and pass-throughs:
```dart
    double? ratePerKgSnapshotUgx,
    double? estimatedWeightKg,
    double? finalWeightKg,
    List<LineItem>? lineItems,
    int? manualAdjustmentUgx,
    int? totalUgx,
    bool clearEstimatedWeight = false,
    bool clearFinalWeight = false,
```
and in the returned `LaundryOrder(...)`:
```dart
      ratePerKgSnapshotUgx: ratePerKgSnapshotUgx ?? this.ratePerKgSnapshotUgx,
      estimatedWeightKg: clearEstimatedWeight
          ? null
          : (estimatedWeightKg ?? this.estimatedWeightKg),
      finalWeightKg:
          clearFinalWeight ? null : (finalWeightKg ?? this.finalWeightKg),
      lineItems: lineItems ?? this.lineItems,
      manualAdjustmentUgx: manualAdjustmentUgx ?? this.manualAdjustmentUgx,
      totalUgx: totalUgx ?? this.totalUgx,
```

In `operator ==`, add to the field comparison chain (before the `proofEvents` length check):
```dart
        other.ratePerKgSnapshotUgx != ratePerKgSnapshotUgx ||
        other.estimatedWeightKg != estimatedWeightKg ||
        other.finalWeightKg != finalWeightKg ||
        other.manualAdjustmentUgx != manualAdjustmentUgx ||
        other.totalUgx != totalUgx ||
```
and add a list comparison for `lineItems` next to the existing `proofEvents` loop:
```dart
    if (lineItems.length != other.lineItems.length) return false;
    for (var i = 0; i < lineItems.length; i++) {
      if (lineItems[i] != other.lineItems[i]) return false;
    }
```

In `hashCode`, add to `Object.hash(...)`:
```dart
        ratePerKgSnapshotUgx,
        estimatedWeightKg,
        finalWeightKg,
        Object.hashAll(lineItems),
        manualAdjustmentUgx,
        totalUgx,
```

> `Object.hash` takes at most 20 positional args. Count the existing args (15) + 6 new = 21. If it overflows, nest: replace the trailing pricing args with a single `Object.hash(ratePerKgSnapshotUgx, estimatedWeightKg, finalWeightKg, Object.hashAll(lineItems), manualAdjustmentUgx, totalUgx)` passed as one argument.

- [ ] **Step 4: Remove the placeholder import from the test**

Delete the `import '.../line_item_helpers.dart';` line from `test/orders/order_pricing_test.dart`.

- [ ] **Step 5: Run to verify it passes**

Run: `flutter test test/orders/order_pricing_test.dart`
Expected: PASS (all 4 tests).

- [ ] **Step 6: Run the full order test suite (regression)**

Run: `flutter test test/orders/`
Expected: PASS — existing order tests still green (the new fields all have defaults).

- [ ] **Step 7: Commit**

```bash
git add lib/src/orders/order.dart test/orders/order_pricing_test.dart
git commit -m "feat(orders): add pricing fields to LaundryOrder"
```

### Task 8: `PricingSettings` domain model

**Files:**
- Create: `lib/src/pricing/pricing_settings.dart`
- Test: `test/pricing/pricing_settings_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:amuwak_staff/src/pricing/pricing_settings.dart';

void main() {
  group('PricingSettings', () {
    test('fromSupabase reads the singleton row', () {
      final s = PricingSettings.fromSupabase({
        'id': 'p1',
        'default_rate_per_kg_ugx': 5000,
        'updated_at': '2026-06-06T10:00:00Z',
        'updated_by': 'staff-1',
      });
      expect(s.id, 'p1');
      expect(s.defaultRatePerKgUgx, 5000);
    });

    test('reads an integer-typed rate as double', () {
      final s = PricingSettings.fromSupabase({
        'id': 'p1',
        'default_rate_per_kg_ugx': 4500,
        'updated_at': '2026-06-06T10:00:00Z',
        'updated_by': null,
      });
      expect(s.defaultRatePerKgUgx, 4500.0);
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/pricing/pricing_settings_test.dart`
Expected: FAIL — file does not exist.

- [ ] **Step 3: Implement `PricingSettings`**

```dart
/// The singleton global pricing configuration (one row in `pricing_settings`).
/// `defaultRatePerKgUgx` is the rate used for any customer without an override.
class PricingSettings {
  const PricingSettings({
    required this.id,
    required this.defaultRatePerKgUgx,
    required this.updatedAt,
    this.updatedBy,
  });

  final String id;
  final double defaultRatePerKgUgx;
  final DateTime updatedAt;
  final String? updatedBy;

  factory PricingSettings.fromSupabase(Map<String, dynamic> r) =>
      PricingSettings(
        id: r['id'] as String,
        defaultRatePerKgUgx:
            (r['default_rate_per_kg_ugx'] as num).toDouble(),
        updatedAt: DateTime.parse(r['updated_at'] as String),
        updatedBy: r['updated_by'] as String?,
      );
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/pricing/pricing_settings_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/pricing/pricing_settings.dart test/pricing/pricing_settings_test.dart
git commit -m "feat(pricing): add PricingSettings domain model"
```

---

## Phase 4 — Serialization (read mappers + write payloads)

### Task 9: Order write payload carries pricing

**Files:**
- Modify: `lib/src/sync/supabase_payloads.dart:16-39`
- Test: `test/sync/supabase_payloads_test.dart` (extend or create)

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:amuwak_staff/src/orders/order.dart';
import 'package:amuwak_staff/src/orders/order_status.dart';
import 'package:amuwak_staff/src/orders/pricing/line_item.dart';
import 'package:amuwak_staff/src/orders/service_type.dart';
import 'package:amuwak_staff/src/sync/supabase_payloads.dart';

void main() {
  test('orderUpsertPayload serializes pricing fields', () {
    final order = LaundryOrder(
      orderId: 'o1',
      orderCode: 'AMW-2026-0001',
      customerName: 'Aisha',
      serviceType: ServiceType.washAndIron,
      status: OrderStatus.pendingPickup,
      timeLabel: 'Pickup: now',
      itemCount: 0,
      phone: '+256 700000000',
      address: 'Kampala',
      notes: '',
      ratePerKgSnapshotUgx: 5000,
      estimatedWeightKg: 2.5,
      lineItems: [LineItem(name: 'Blanket', amountUgx: 8000)],
      manualAdjustmentUgx: -1000,
      totalUgx: 19500,
    );
    final p = orderUpsertPayload(order,
        actorStaffId: 's1', now: DateTime.utc(2026, 6, 6));
    expect(p['rate_per_kg_snapshot_ugx'], 5000);
    expect(p['estimated_weight_kg'], 2.5);
    expect(p['final_weight_kg'], isNull);
    expect(p['line_items'], [
      {'name': 'Blanket', 'amount_ugx': 8000}
    ]);
    expect(p['manual_adjustment_ugx'], -1000);
    expect(p['total_ugx'], 19500);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/sync/supabase_payloads_test.dart`
Expected: FAIL — keys absent from the payload.

- [ ] **Step 3: Extend `orderUpsertPayload`**

In `lib/src/sync/supabase_payloads.dart`, add these keys to the map returned by `orderUpsertPayload` (before `'intake_recorded_by'`):

```dart
      'rate_per_kg_snapshot_ugx': order.ratePerKgSnapshotUgx,
      'estimated_weight_kg': order.estimatedWeightKg,
      'final_weight_kg': order.finalWeightKg,
      'line_items': order.lineItems.map((i) => i.toJson()).toList(),
      'manual_adjustment_ugx': order.manualAdjustmentUgx,
      'total_ugx': order.totalUgx,
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/sync/supabase_payloads_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/sync/supabase_payloads.dart test/sync/supabase_payloads_test.dart
git commit -m "feat(sync): serialize order pricing fields in upsert payload"
```

### Task 10: Customer custom-rate read + write

**Files:**
- Modify: `lib/src/sync/supabase_mappers.dart:24-33` (read)
- Modify: `lib/src/sync/supabase_payloads.dart:50-62` (write)
- Modify: `lib/src/data/tables/...` already done in Task 6
- Test: `test/sync/customer_custom_rate_test.dart` (new)

> The Drift `Customer` data class now has `customRatePerKgUgx` (Task 6). `customerFromSupabase` builds that data class, so it must read the new key.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:amuwak_staff/src/data/app_database.dart';
import 'package:amuwak_staff/src/sync/supabase_mappers.dart';
import 'package:amuwak_staff/src/sync/supabase_payloads.dart';

void main() {
  test('customerFromSupabase reads custom_rate_per_kg_ugx', () {
    final c = customerFromSupabase({
      'id': 'c1',
      'name': 'Aisha',
      'phone': '+256 700000000',
      'address': 'Kampala',
      'notes': null,
      'custom_rate_per_kg_ugx': 4000,
      'created_at': '2026-06-06T10:00:00Z',
      'updated_at': '2026-06-06T10:00:00Z',
      'deleted_at': null,
    });
    expect(c.customRatePerKgUgx, 4000.0);
  });

  test('customerUpsertPayload writes custom_rate_per_kg_ugx (incl. null)', () {
    final c = Customer(
      id: 'c1',
      name: 'Aisha',
      phone: '+256 700000000',
      address: 'Kampala',
      notes: null,
      customRatePerKgUgx: null,
      createdAt: DateTime.utc(2026, 6, 6),
      updatedAt: DateTime.utc(2026, 6, 6),
      deletedAt: null,
    );
    final p = customerUpsertPayload(c, now: DateTime.utc(2026, 6, 6));
    expect(p.containsKey('custom_rate_per_kg_ugx'), isTrue);
    expect(p['custom_rate_per_kg_ugx'], isNull);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/sync/customer_custom_rate_test.dart`
Expected: FAIL — `customRatePerKgUgx` not set / key absent.

- [ ] **Step 3: Wire read + write**

In `lib/src/sync/supabase_mappers.dart`, add to `customerFromSupabase(...)`:
```dart
      customRatePerKgUgx:
          (r['custom_rate_per_kg_ugx'] as num?)?.toDouble(),
```

In `lib/src/sync/supabase_payloads.dart`, add to `customerUpsertPayload(...)` (after `'notes'`):
```dart
      'custom_rate_per_kg_ugx': customer.customRatePerKgUgx,
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/sync/customer_custom_rate_test.dart`
Expected: PASS.

- [ ] **Step 5: Run customer/sync regressions**

Run: `flutter test test/sync/`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/src/sync/supabase_mappers.dart lib/src/sync/supabase_payloads.dart test/sync/customer_custom_rate_test.dart
git commit -m "feat(sync): read/write customer custom_rate_per_kg_ugx"
```

---

## Phase 5 — Repositories

### Task 11: `PricingSettingsRepository` + providers

**Files:**
- Create: `lib/src/pricing/pricing_settings_repository.dart`
- Create: `lib/src/pricing/pricing_providers.dart`
- Test: `test/pricing/pricing_settings_repository_test.dart`

> Read pattern: a one-shot `select().limit(1)` (the row is a singleton; no stream needed). Write pattern: `update` the single row. Mirror the `SupabaseClient` injection used by `OrdersRepository`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:amuwak_staff/src/pricing/pricing_settings.dart';
import 'package:amuwak_staff/src/pricing/pricing_settings_repository.dart';

void main() {
  group('PricingSettingsRepository', () {
    test('throws a clear error when no settings row exists', () async {
      final repo = PricingSettingsRepository.forTest(fetchRows: () async => []);
      expect(repo.fetch, throwsA(isA<StateError>()));
    });

    test('returns the first row when present', () async {
      final repo = PricingSettingsRepository.forTest(fetchRows: () async => [
            {
              'id': 'p1',
              'default_rate_per_kg_ugx': 5000,
              'updated_at': '2026-06-06T10:00:00Z',
              'updated_by': null,
            }
          ]);
      final s = await repo.fetch();
      expect(s.defaultRatePerKgUgx, 5000);
    });
  });
}
```

> This test uses a `forTest` seam (an injectable fetch thunk) to avoid mocking the whole Supabase client — the project's repos are otherwise client-backed. Provide both the real `SupabaseClient` constructor and this seam.

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/pricing/pricing_settings_repository_test.dart`
Expected: FAIL — file does not exist.

- [ ] **Step 3: Implement the repository**

`lib/src/pricing/pricing_settings_repository.dart`:

```dart
import 'package:supabase_flutter/supabase_flutter.dart';

import 'pricing_settings.dart';

typedef _FetchRows = Future<List<Map<String, dynamic>>> Function();

/// Reads and updates the singleton `pricing_settings` row.
///
/// Reads are one-shot (the row is a singleton; no realtime needed). The settings
/// table is intentionally not in the realtime publication — see migration 0019.
class PricingSettingsRepository {
  PricingSettingsRepository(this._supabase, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now,
        _fetchRowsOverride = null;

  /// Test seam: inject the raw row fetch so unit tests don't mock SupabaseClient.
  PricingSettingsRepository.forTest({required _FetchRows fetchRows})
      : _supabase = null,
        _clock = DateTime.now,
        _fetchRowsOverride = fetchRows;

  final SupabaseClient? _supabase;
  final DateTime Function() _clock;
  final _FetchRows? _fetchRowsOverride;

  Future<List<Map<String, dynamic>>> _fetchRows() {
    final override = _fetchRowsOverride;
    if (override != null) return override();
    return _supabase!
        .from('pricing_settings')
        .select()
        .limit(1)
        .then((rows) => rows.cast<Map<String, dynamic>>());
  }

  /// Fetches the singleton settings. Throws [StateError] if the row is missing
  /// (corrupted state the singleton index should prevent) so the UI can show
  /// "Pricing settings missing — contact admin." rather than silently defaulting.
  Future<PricingSettings> fetch() async {
    final rows = await _fetchRows();
    if (rows.isEmpty) {
      throw StateError('pricing_settings has no row');
    }
    return PricingSettings.fromSupabase(rows.first);
  }

  /// Updates the global default rate on the singleton row.
  Future<void> updateDefaultRate(double ratePerKgUgx,
      {required String actorStaffId}) async {
    final id = (await fetch()).id;
    await _supabase!.from('pricing_settings').update({
      'default_rate_per_kg_ugx': ratePerKgUgx,
      'updated_at': _clock().toUtc().toIso8601String(),
      'updated_by': actorStaffId,
    }).eq('id', id);
  }
}
```

`lib/src/pricing/pricing_providers.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../sync/repository_providers.dart';
import 'pricing_settings_repository.dart';

final pricingSettingsRepositoryProvider =
    Provider<PricingSettingsRepository>(
  (ref) => PricingSettingsRepository(ref.watch(supabaseClientProvider)),
);

/// The resolved global default rate, used by the new-pickup rate display when a
/// customer has no override. Re-read on invalidation (e.g. after the settings
/// screen saves).
final defaultRatePerKgUgxProvider = FutureProvider<double>(
  (ref) async => (await ref
          .watch(pricingSettingsRepositoryProvider)
          .fetch())
      .defaultRatePerKgUgx,
);
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/pricing/pricing_settings_repository_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/pricing/pricing_settings_repository.dart lib/src/pricing/pricing_providers.dart test/pricing/pricing_settings_repository_test.dart
git commit -m "feat(pricing): add PricingSettingsRepository and providers"
```

### Task 12: `OrdersRepository` recomputes total on write + resolves rate on create

**Files:**
- Modify: `lib/src/sync/orders_repository.dart:128-134`
- Test: `test/sync/orders_repository_pricing_test.dart` (new)

> Two responsibilities: (a) `upsertOrder` always overwrites `total_ugx` from `recomputeTotal` so a stale caller total can never persist; (b) a new `resolveRatePerKg(...)` helper computes `customer.customRatePerKgUgx ?? settings.defaultRatePerKgUgx`, used by `NewPickupScreen` to freeze the snapshot. Keep (b) as a pure helper on the repo for testability.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:amuwak_staff/src/orders/order.dart';
import 'package:amuwak_staff/src/orders/order_status.dart';
import 'package:amuwak_staff/src/orders/service_type.dart';
import 'package:amuwak_staff/src/sync/orders_repository.dart';

void main() {
  group('OrdersRepository pricing', () {
    test('recomputeOrderTotal overwrites a stale caller total', () {
      final stale = LaundryOrder(
        orderId: 'o1',
        customerName: 'A',
        serviceType: ServiceType.washOnly,
        status: OrderStatus.pendingPickup,
        timeLabel: 'Pickup: now',
        itemCount: 0,
        phone: 'p',
        address: 'a',
        notes: '',
        ratePerKgSnapshotUgx: 5000,
        finalWeightKg: 4,
        totalUgx: 999999, // deliberately wrong
      );
      final corrected = OrdersRepository.recomputeOrderTotal(stale);
      expect(corrected.totalUgx, 20000); // 4 * 5000
    });

    test('resolveRatePerKg prefers the customer override', () {
      expect(
        OrdersRepository.resolveRatePerKg(
            customRate: 4000, defaultRate: 5000),
        4000,
      );
    });

    test('resolveRatePerKg falls back to the default when no override', () {
      expect(
        OrdersRepository.resolveRatePerKg(
            customRate: null, defaultRate: 5000),
        5000,
      );
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/sync/orders_repository_pricing_test.dart`
Expected: FAIL — static methods do not exist.

- [ ] **Step 3: Add the helpers and apply on write**

In `lib/src/sync/orders_repository.dart`, add the imports:
```dart
import '../orders/pricing/pricing_calculator.dart';
import '../orders/pricing/pricing_inputs.dart';
```

Add two static helpers to the `OrdersRepository` class:
```dart
  /// Returns a copy of [order] with `totalUgx` recomputed from its pricing
  /// inputs. The single chokepoint that keeps the stored total honest — a
  /// caller can never persist a total that disagrees with the weights/rate/
  /// line-items/adjustment.
  static LaundryOrder recomputeOrderTotal(LaundryOrder order) {
    final t = recomputeTotal(PricingInputs(
      ratePerKgUgx: order.ratePerKgSnapshotUgx,
      estimatedWeightKg: order.estimatedWeightKg,
      finalWeightKg: order.finalWeightKg,
      lineItems: order.lineItems,
      manualAdjustmentUgx: order.manualAdjustmentUgx,
    ));
    return order.copyWith(totalUgx: t.total);
  }

  /// Resolves the rate to freeze into a new order: the customer's override if
  /// set, otherwise the global default.
  static double resolveRatePerKg({
    required double? customRate,
    required double defaultRate,
  }) =>
      customRate ?? defaultRate;
```

In `upsertOrder`, recompute before building the payload:
```dart
  Future<void> upsertOrder(LaundryOrder order,
      {required String actorStaffId}) async {
    final now = _clock();
    final priced = recomputeOrderTotal(order);
    await _supabase
        .from('orders')
        .upsert(orderUpsertPayload(priced, actorStaffId: actorStaffId, now: now));
  }
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/sync/orders_repository_pricing_test.dart`
Expected: PASS.

- [ ] **Step 5: Run sync regressions**

Run: `flutter test test/sync/`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/src/sync/orders_repository.dart test/sync/orders_repository_pricing_test.dart
git commit -m "feat(sync): recompute order total on write; resolve rate snapshot"
```

---

## Phase 6 — UI

> Shared widget note: Tasks 16 and 17 both need a line-item editor and a total card. Build them once in `lib/src/orders/pricing/pricing_section.dart` (Task 14) and reuse. All money rendering uses `formatUgx` (Task 5).

### Task 13: Shared pricing widgets (`pricing_section.dart`)

**Files:**
- Create: `lib/src/orders/pricing/pricing_section.dart`
- Test: `test/orders/pricing/pricing_section_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:amuwak_staff/src/orders/pricing/line_item.dart';
import 'package:amuwak_staff/src/orders/pricing/pricing_section.dart';

void main() {
  testWidgets('LineItemsEditor shows items and fires onRemove', (tester) async {
    var removed = -1;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LineItemsEditor(
          items: [LineItem(name: 'Blanket', amountUgx: 8000)],
          onAdd: () {},
          onRemove: (i) => removed = i,
        ),
      ),
    ));
    expect(find.text('Blanket'), findsOneWidget);
    expect(find.text('USh 8,000'), findsOneWidget);
    await tester.tap(find.byKey(const Key('remove_line_item_0')));
    expect(removed, 0);
  });

  testWidgets('TotalCard renders the total and a Provisional badge', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: TotalCard(totalUgx: 23000, isProvisional: true),
      ),
    ));
    expect(find.text('USh 23,000'), findsOneWidget);
    expect(find.text('Provisional'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/orders/pricing/pricing_section_test.dart`
Expected: FAIL — file does not exist.

- [ ] **Step 3: Implement the shared widgets**

```dart
import 'package:flutter/material.dart';

import '../../shared/format_ugx.dart';
import '../../shared/theme/app_card.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import 'line_item.dart';

/// Editable list of free-form line items, with an "Add item" button. Stateless:
/// the parent owns the list and re-renders on change.
class LineItemsEditor extends StatelessWidget {
  const LineItemsEditor({
    super.key,
    required this.items,
    required this.onAdd,
    required this.onRemove,
  });

  final List<LineItem> items;
  final VoidCallback onAdd;
  final void Function(int index) onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              children: [
                Expanded(child: Text(items[i].name)),
                Text(formatUgx(items[i].amountUgx)),
                IconButton(
                  key: Key('remove_line_item_$i'),
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: () => onRemove(i),
                ),
              ],
            ),
          ),
        TextButton.icon(
          key: const Key('add_line_item'),
          onPressed: onAdd,
          icon: const Icon(Icons.add),
          label: const Text('Add item'),
        ),
      ],
    );
  }
}

/// Prominent total display with an optional "Provisional" badge (shown until a
/// final weight is recorded).
class TotalCard extends StatelessWidget {
  const TotalCard({
    super.key,
    required this.totalUgx,
    required this.isProvisional,
  });

  final int totalUgx;
  final bool isProvisional;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return AppCard(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Total', style: textTheme.bodySmall),
              Text(formatUgx(totalUgx), style: textTheme.headlineMedium),
            ],
          ),
          if (isProvisional)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: AppColors.secondaryText.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text('Provisional'),
            ),
        ],
      ),
    );
  }
}

/// Shows a bottom sheet collecting a line-item name + amount. Returns the
/// validated [LineItem], or null if cancelled / invalid.
Future<LineItem?> showAddLineItemSheet(BuildContext context) {
  final nameController = TextEditingController();
  final amountController = TextEditingController();
  return showModalBottomSheet<LineItem>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl,
        MediaQuery.of(sheetContext).viewInsets.bottom + AppSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('line_item_name'),
            controller: nameController,
            decoration: const InputDecoration(labelText: 'Item (e.g. Blanket)'),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            key: const Key('line_item_amount'),
            controller: amountController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Amount (UGX)'),
          ),
          const SizedBox(height: AppSpacing.lg),
          ElevatedButton(
            key: const Key('line_item_save'),
            onPressed: () {
              final name = nameController.text.trim();
              final amount = int.tryParse(amountController.text.trim());
              if (name.isEmpty || amount == null || amount < 0) {
                Navigator.pop(sheetContext); // invalid → cancel
                return;
              }
              Navigator.pop(sheetContext, LineItem(name: name, amountUgx: amount));
            },
            child: const Text('Add'),
          ),
        ],
      ),
    ),
  );
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/orders/pricing/pricing_section_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/orders/pricing/pricing_section.dart test/orders/pricing/pricing_section_test.dart
git commit -m "feat(orders): shared line-item editor and total card widgets"
```

### Task 14: `NewPickupScreen` shows the resolved rate

**Files:**
- Modify: `lib/src/orders/new_pickup_screen.dart`
- Modify: `lib/src/dashboard/staff_dashboard_screen.dart:178-190` (pass the resolved default rate in)
- Test: `test/orders/new_pickup_rate_test.dart` (new)

> `NewPickupScreen` already receives `customersRepo`/`ordersRepo` and uses constructor injection (no Riverpod inside). Follow that style: add a `required double defaultRatePerKgUgx` parameter (the dashboard resolves it from `defaultRatePerKgUgxProvider` before pushing). The displayed rate is `matchedCustomer.customRatePerKgUgx ?? defaultRatePerKgUgx`; it updates when a customer match is applied.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:amuwak_staff/src/orders/new_pickup_screen.dart';
// ... reuse the fakes/builders from the existing new_pickup_screen_test.dart ...

void main() {
  testWidgets('shows the default rate when no customer is matched',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: NewPickupScreen(
        // existing required args from the current test harness, plus:
        defaultRatePerKgUgx: 5000,
        // customersRepo / ordersRepo / generators / geolocate / etc.
      ),
    ));
    expect(find.text('Rate: USh 5,000/kg'), findsOneWidget);
  });
}
```

> Copy the constructor-arg scaffolding from the existing `test/auth/...`-style new-pickup test (`test/` has a new-pickup widget test paired with the screen — locate it and reuse its fakes). Only the `defaultRatePerKgUgx` arg and the rate assertion are new.

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/orders/new_pickup_rate_test.dart`
Expected: FAIL — `defaultRatePerKgUgx` is not a parameter; no rate text rendered.

- [ ] **Step 3: Add the parameter, state, and display**

In `lib/src/orders/new_pickup_screen.dart`:

Add the import:
```dart
import '../shared/format_ugx.dart';
```

Add to the constructor + fields:
```dart
    required this.defaultRatePerKgUgx,
```
```dart
  final double defaultRatePerKgUgx;
```

Add a state field tracking the matched customer's override (set it in `_showCustomerMatchSheet` when "Use this customer" is chosen, clear it when the phone field changes):
```dart
  double? _matchedCustomerRate;
```

In `_showCustomerMatchSheet`, inside the `if (useIt == true && mounted)` `setState`, add:
```dart
        _matchedCustomerRate = match.customRatePerKgUgx;
```
In the phone `onChanged` (where `_matchedCustomerId = null;` is set), also add:
```dart
                _matchedCustomerRate = null;
```

Add a getter:
```dart
  double get _resolvedRate => _matchedCustomerRate ?? widget.defaultRatePerKgUgx;
```

In `build`, add a read-only line under the address field (after the address `TextFormField` + its `SizedBox`):
```dart
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Rate: ${formatUgx(_resolvedRate.round())}/kg',
                key: const Key('np_rate'),
                style: const TextStyle(color: AppColors.secondaryText),
              ),
            ),
            const SizedBox(height: 12),
```

In `_onSubmit`, set the snapshot when building the `LaundryOrder`:
```dart
      ratePerKgSnapshotUgx: _resolvedRate,
```

- [ ] **Step 4: Wire the dashboard to resolve and pass the rate**

In `lib/src/dashboard/staff_dashboard_screen.dart`, in `_handleNewPickup`, resolve the default before pushing (read the provider; if it's still loading, fall back to a one-shot fetch). Add to the `NewPickupScreen(...)` constructor call:
```dart
          defaultRatePerKgUgx:
              ref.read(defaultRatePerKgUgxProvider).valueOrNull ??
                  await ref.read(pricingSettingsRepositoryProvider).fetch()
                      .then((s) => s.defaultRatePerKgUgx),
```
and add the import:
```dart
import '../pricing/pricing_providers.dart';
```

> If `fetch()` throws (settings missing), surface the existing "Session expired"-style SnackBar pattern with "Pricing settings missing — contact admin." and return without opening the form.

- [ ] **Step 5: Run to verify it passes**

Run: `flutter test test/orders/new_pickup_rate_test.dart`
Expected: PASS.

- [ ] **Step 6: Run new-pickup + dashboard regressions**

Run: `flutter test test/dashboard/ test/orders/`
Expected: PASS (update any existing new-pickup test that constructs `NewPickupScreen` to pass `defaultRatePerKgUgx: 5000`).

- [ ] **Step 7: Commit**

```bash
git add lib/src/orders/new_pickup_screen.dart lib/src/dashboard/staff_dashboard_screen.dart test/orders/new_pickup_rate_test.dart
git commit -m "feat(orders): show resolved rate on New Pickup and freeze snapshot"
```

### Task 15: `PickupCaptureScreen` — estimate + line items + provisional total

**Files:**
- Modify: `lib/src/orders/proof/pickup_capture_screen.dart`
- Test: `test/orders/proof/pickup_capture_pricing_test.dart` (new)

> The estimate and line items belong in the `_Stage.collecting` view. The provisional total recomputes locally on every change (using `recomputeTotal` with the order's frozen `ratePerKgSnapshotUgx`). On `_onDone`, persist `estimatedWeightKg`, `lineItems`, and the recomputed `totalUgx` via `ordersRepo.upsertOrder` **in addition** to the existing proof-event + status-update writes. Status still advances to `inProgress` exactly as today (see Pre-flight #1).

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// reuse the fakes from the existing pickup capture test (photoStorage, repos)
import 'package:amuwak_staff/src/orders/proof/pickup_capture_screen.dart';

void main() {
  testWidgets('shows a live provisional total from the estimated weight',
      (tester) async {
    // order with ratePerKgSnapshotUgx: 5000
    // pump PickupCaptureScreen with the existing fakes
    // enter '3' into the estimated-weight field (Key('pickup_estimated_weight'))
    // expect provisional total 'USh 15,000' and a 'Provisional' badge
  });
}
```

> Flesh out the test body using the harness in the existing `test/orders/proof/delivery_capture_screen_test.dart` / pickup capture test (fakes for `ProofPhotoStorage`, `OrdersRepository`, `ProofEventsRepository`). The new assertions: entering `3` in `Key('pickup_estimated_weight')` renders `USh 15,000` and `Provisional`.

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/orders/proof/pickup_capture_pricing_test.dart`
Expected: FAIL — no estimated-weight field, no total.

- [ ] **Step 3: Add estimate + line items + total to the collecting stage**

In `lib/src/orders/proof/pickup_capture_screen.dart`:

Add imports:
```dart
import '../pricing/line_item.dart';
import '../pricing/pricing_calculator.dart';
import '../pricing/pricing_inputs.dart';
import '../pricing/pricing_section.dart';
```

Add state fields:
```dart
  final TextEditingController _estimatedWeightController = TextEditingController();
  List<LineItem> _lineItems = [];
```

Add a getter for the live total:
```dart
  OrderTotal get _provisionalTotal => recomputeTotal(PricingInputs(
        ratePerKgUgx: widget.order.ratePerKgSnapshotUgx,
        estimatedWeightKg:
            double.tryParse(_estimatedWeightController.text.trim()),
        lineItems: _lineItems,
      ));
```

In `_buildCollecting`, after the photos section (before the notes field), add:
```dart
        const SizedBox(height: 20),
        Text('Estimated weight (kg)',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        TextFormField(
          key: const Key('pickup_estimated_weight'),
          controller: _estimatedWeightController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(border: OutlineInputBorder()),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 20),
        Text('Special items', style: Theme.of(context).textTheme.titleMedium),
        LineItemsEditor(
          items: _lineItems,
          onAdd: () async {
            final item = await showAddLineItemSheet(context);
            if (item != null) setState(() => _lineItems = [..._lineItems, item]);
          },
          onRemove: (i) => setState(() {
            _lineItems = [..._lineItems]..removeAt(i);
          }),
        ),
        const SizedBox(height: 12),
        TotalCard(
          totalUgx: _provisionalTotal.total,
          isProvisional: _provisionalTotal.isProvisional,
        ),
```

In `_onDone`, after the successful `updateStatus` call and before `Navigator.pop`, persist the pricing onto the order:
```dart
    try {
      await widget.ordersRepo.upsertOrder(
        widget.order.copyWith(
          status: OrderStatus.inProgress,
          estimatedWeightKg:
              double.tryParse(_estimatedWeightController.text.trim()),
          lineItems: _lineItems,
        ),
        actorStaffId: widget.actorStaffId,
      );
    } catch (_) {
      // Pricing persist is best-effort here; the status already advanced. Log
      // and continue — staff can correct totals later on the details screen.
    }
```

> `upsertOrder` recomputes `total_ugx` itself (Task 12), so the caller doesn't pass a total. Note: `upsertOrder` overwrites `created_at`/`created_by` (see its doc comment caveat). Confirm with the implementer that this is acceptable at pickup time, OR add a dedicated `updatePricing(...)` method on `OrdersRepository` that updates only the pricing columns + `updated_at` (preferred — mirrors `updateStatus`). **If in doubt, add `updatePricing` and call it here instead of `upsertOrder`.**

Dispose the controller in `dispose()`:
```dart
    _estimatedWeightController.dispose();
```

- [ ] **Step 4: (Recommended) add `OrdersRepository.updatePricing`**

To avoid clobbering creation columns, add to `OrdersRepository`:
```dart
  /// Updates only the pricing columns (+ updated_at), recomputing total_ugx.
  /// Unlike [upsertOrder] this never touches created_at/created_by.
  Future<void> updatePricing(LaundryOrder order,
      {required String actorStaffId}) async {
    final priced = recomputeOrderTotal(order);
    final updated = await _supabase.from('orders').update({
      'estimated_weight_kg': priced.estimatedWeightKg,
      'final_weight_kg': priced.finalWeightKg,
      'line_items': priced.lineItems.map((i) => i.toJson()).toList(),
      'manual_adjustment_ugx': priced.manualAdjustmentUgx,
      'total_ugx': priced.totalUgx,
      'updated_at': _clock().toUtc().toIso8601String(),
    }).eq('id', priced.orderId).select('id');
    if (updated.isEmpty) {
      throw StateError('updatePricing: no order with id "${priced.orderId}"');
    }
  }
```
Then call `widget.ordersRepo.updatePricing(...)` in Step 3 instead of `upsertOrder`. Add a unit test for `updatePricing` recomputing the total (mirror Task 12's test).

- [ ] **Step 5: Run to verify it passes**

Run: `flutter test test/orders/proof/pickup_capture_pricing_test.dart`
Expected: PASS.

- [ ] **Step 6: Run proof regressions**

Run: `flutter test test/orders/proof/`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/src/orders/proof/pickup_capture_screen.dart lib/src/sync/orders_repository.dart test/orders/proof/pickup_capture_pricing_test.dart
git commit -m "feat(orders): capture estimate + line items with provisional total at pickup"
```

### Task 16: `OrderDetailsScreen` — editable Pricing block with final weight

**Files:**
- Modify: `lib/src/orders/order_details_screen.dart`
- Test: `test/orders/order_details_pricing_test.dart` (new)

> A new "Pricing" `_DetailsSection`, visible once status is past `pendingPickup` (i.e. after pickup). It shows the read-only frozen rate, an editable final-weight field, the line-item editor, a manual-adjustment field, and the live total (provisional until a final weight is entered). A "Save pricing" button calls `ordersRepo.updatePricing` (Task 15 Step 4) and optimistically updates `_order`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// reuse the fakes from the existing order details test harness
import 'package:amuwak_staff/src/orders/order_details_screen.dart';

void main() {
  testWidgets('shows the frozen rate and recomputes total on final weight',
      (tester) async {
    // order: status inProgress, ratePerKgSnapshotUgx 5000, no weights
    // pump OrderDetailsScreen with fakes
    // expect 'Rate at order: USh 5,000/kg' present
    // enter '4' in Key('details_final_weight')
    // expect total 'USh 20,000' and NO 'Provisional' badge
  });
}
```

> Build the body from the existing order-details widget test harness (it constructs `OrderDetailsScreen` with `photoStorage`, `pickPhoto`, `cameraViewBuilder`, `ordersRepo`, `proofEventsRepo`, `actorStaffId`). New assertions only.

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/orders/order_details_pricing_test.dart`
Expected: FAIL — no pricing section.

- [ ] **Step 3: Add the editable Pricing section**

In `lib/src/orders/order_details_screen.dart`:

Add imports:
```dart
import '../shared/format_ugx.dart';
import 'pricing/line_item.dart';
import 'pricing/pricing_calculator.dart';
import 'pricing/pricing_inputs.dart';
import 'pricing/pricing_section.dart';
```

Add state controllers/fields to `_OrderDetailsScreenState`:
```dart
  late final TextEditingController _finalWeightController;
  late final TextEditingController _manualAdjustmentController;
  late List<LineItem> _lineItems;
```

In `initState`, seed them from `_order`:
```dart
    _finalWeightController = TextEditingController(
        text: _order.finalWeightKg?.toString() ?? '');
    _manualAdjustmentController = TextEditingController(
        text: _order.manualAdjustmentUgx == 0
            ? ''
            : _order.manualAdjustmentUgx.toString());
    _lineItems = [..._order.lineItems];
```

Add a `dispose` override (the class currently has none):
```dart
  @override
  void dispose() {
    _finalWeightController.dispose();
    _manualAdjustmentController.dispose();
    super.dispose();
  }
```

Add the live-total getter:
```dart
  OrderTotal get _pricingTotal => recomputeTotal(PricingInputs(
        ratePerKgUgx: _order.ratePerKgSnapshotUgx,
        estimatedWeightKg: _order.estimatedWeightKg,
        finalWeightKg: double.tryParse(_finalWeightController.text.trim()),
        lineItems: _lineItems,
        manualAdjustmentUgx:
            int.tryParse(_manualAdjustmentController.text.trim()) ?? 0,
      ));
```

Add the save handler:
```dart
  Future<void> _savePricing() async {
    final updated = _order.copyWith(
      finalWeightKg: double.tryParse(_finalWeightController.text.trim()),
      clearFinalWeight: _finalWeightController.text.trim().isEmpty,
      lineItems: _lineItems,
      manualAdjustmentUgx:
          int.tryParse(_manualAdjustmentController.text.trim()) ?? 0,
    );
    try {
      await widget.ordersRepo
          .updatePricing(updated, actorStaffId: widget.actorStaffId);
      if (!mounted) return;
      setState(() => _order = OrdersRepository.recomputeOrderTotal(updated));
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('Pricing saved.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save pricing — please retry.')),
      );
    }
  }
```
> Add `import '../sync/orders_repository.dart';` if not already present (it is — `ordersRepo` is typed `OrdersRepository`).

In `build`, insert a Pricing section after the "Laundry details" section, gated on status:
```dart
                      if (_order.status != OrderStatus.pendingPickup) ...[
                        const SizedBox(height: AppSpacing.md),
                        _DetailsSection(
                          title: 'Pricing',
                          children: [
                            _DetailRow(
                              icon: Icons.scale_outlined,
                              label: 'Rate',
                              value:
                                  '${formatUgx(_order.ratePerKgSnapshotUgx.round())}/kg',
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            TextFormField(
                              key: const Key('details_final_weight'),
                              controller: _finalWeightController,
                              keyboardType: const TextInputType
                                  .numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                  labelText: 'Final weight (kg)'),
                              onChanged: (_) => setState(() {}),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            LineItemsEditor(
                              items: _lineItems,
                              onAdd: () async {
                                final item = await showAddLineItemSheet(context);
                                if (item != null) {
                                  setState(() => _lineItems = [..._lineItems, item]);
                                }
                              },
                              onRemove: (i) => setState(() {
                                _lineItems = [..._lineItems]..removeAt(i);
                              }),
                            ),
                            TextFormField(
                              key: const Key('details_manual_adjustment'),
                              controller: _manualAdjustmentController,
                              keyboardType: const TextInputType
                                  .numberWithOptions(signed: true),
                              decoration: const InputDecoration(
                                  labelText: 'Manual adjustment (UGX, +/-)'),
                              onChanged: (_) => setState(() {}),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            TotalCard(
                              totalUgx: _pricingTotal.total,
                              isProvisional: _pricingTotal.isProvisional,
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            ElevatedButton(
                              key: const Key('details_save_pricing'),
                              onPressed: _savePricing,
                              child: const Text('Save pricing'),
                            ),
                          ],
                        ),
                      ],
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/orders/order_details_pricing_test.dart`
Expected: PASS.

- [ ] **Step 5: Run order details regressions**

Run: `flutter test test/orders/`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/src/orders/order_details_screen.dart test/orders/order_details_pricing_test.dart
git commit -m "feat(orders): editable pricing block with final weight on Order Details"
```

### Task 17: Pricing settings screen + Account-tab entry

**Files:**
- Create: `lib/src/pricing/pricing_settings_screen.dart`
- Modify: `lib/src/dashboard/staff_dashboard_screen.dart` (`_AccountTab` + a nav handler)
- Test: `test/pricing/pricing_settings_screen_test.dart` (new)

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:amuwak_staff/src/pricing/pricing_settings.dart';
import 'package:amuwak_staff/src/pricing/pricing_settings_screen.dart';

void main() {
  testWidgets('renders the current default rate and saves a new value',
      (tester) async {
    double? saved;
    await tester.pumpWidget(MaterialApp(
      home: PricingSettingsScreen(
        load: () async => PricingSettings(
          id: 'p1',
          defaultRatePerKgUgx: 5000,
          updatedAt: DateTime.utc(2026, 6, 6),
        ),
        save: (rate) async => saved = rate,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('5000'), findsOneWidget); // pre-filled
    await tester.enterText(find.byKey(const Key('settings_rate')), '6000');
    await tester.tap(find.byKey(const Key('settings_save')));
    await tester.pump();
    expect(saved, 6000);
  });
}
```

> The screen takes injectable `load`/`save` callbacks (test seam), defaulting in the dashboard to the repository. This keeps the widget test free of Supabase mocking, matching the `signOut` seam pattern already used by `StaffDashboardScreen`.

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/pricing/pricing_settings_screen_test.dart`
Expected: FAIL — file does not exist.

- [ ] **Step 3: Implement the screen**

```dart
import 'package:flutter/material.dart';

import '../shared/format_ugx.dart';
import '../shared/theme/app_spacing.dart';
import 'pricing_settings.dart';

typedef LoadSettingsFn = Future<PricingSettings> Function();
typedef SaveRateFn = Future<void> Function(double ratePerKgUgx);

class PricingSettingsScreen extends StatefulWidget {
  const PricingSettingsScreen({
    super.key,
    required this.load,
    required this.save,
  });

  final LoadSettingsFn load;
  final SaveRateFn save;

  @override
  State<PricingSettingsScreen> createState() => _PricingSettingsScreenState();
}

class _PricingSettingsScreenState extends State<PricingSettingsScreen> {
  final _controller = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await widget.load();
      if (!mounted) return;
      setState(() {
        _controller.text = s.defaultRatePerKgUgx.round().toString();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Pricing settings missing — contact admin.';
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    final rate = double.tryParse(_controller.text.trim());
    if (rate == null || rate <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a rate greater than 0.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.save(rate);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
            content: Text('Default rate set to ${formatUgx(rate.round())}/kg.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save — please retry.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pricing settings')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!))
                : ListView(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    children: [
                      Text('Default rate per kg (UGX)',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: AppSpacing.sm),
                      TextField(
                        key: const Key('settings_rate'),
                        controller: _controller,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      ElevatedButton(
                        key: const Key('settings_save'),
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Save'),
                      ),
                    ],
                  ),
      ),
    );
  }
}
```

- [ ] **Step 4: Add the Account-tab entry**

In `lib/src/dashboard/staff_dashboard_screen.dart`:

Add imports:
```dart
import '../pricing/pricing_providers.dart';
import '../pricing/pricing_settings_screen.dart';
```

Change `_AccountTab` to accept an `onOpenPricingSettings` callback and render a tappable row (use the existing `AppCard(onTap: ...)` pattern from `_ActionButton`). In `_AccountTab.build`, add before the Sign-out button:
```dart
        AppCard(
          onTap: onOpenPricingSettings,
          child: Row(
            children: [
              Icon(Icons.payments_outlined, color: colorScheme.primary),
              const SizedBox(width: AppSpacing.md),
              const Expanded(child: Text('Pricing settings')),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg2),
```
Add the field + constructor param to `_AccountTab` (`final VoidCallback onOpenPricingSettings;`).

In `_StaffDashboardScreenState`, add the handler and pass it where `_AccountTab` is built (`3 => _AccountTab(onSignOut: _onSignOutPressed, onOpenPricingSettings: _openPricingSettings)`):
```dart
  void _openPricingSettings() {
    final staffId = ref.read(currentUserIdProvider);
    if (staffId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session expired — please sign in again.')),
      );
      return;
    }
    final repo = ref.read(pricingSettingsRepositoryProvider);
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PricingSettingsScreen(
          load: repo.fetch,
          save: (rate) =>
              repo.updateDefaultRate(rate, actorStaffId: staffId),
        ),
      ),
    ).then((_) => ref.invalidate(defaultRatePerKgUgxProvider));
  }
```

- [ ] **Step 5: Run to verify it passes**

Run: `flutter test test/pricing/pricing_settings_screen_test.dart`
Expected: PASS.

- [ ] **Step 6: Run dashboard regressions**

Run: `flutter test test/dashboard/`
Expected: PASS (update the existing dashboard test if it pumps `_AccountTab` or asserts on tab 3).

- [ ] **Step 7: Commit**

```bash
git add lib/src/pricing/pricing_settings_screen.dart lib/src/dashboard/staff_dashboard_screen.dart test/pricing/pricing_settings_screen_test.dart
git commit -m "feat(pricing): pricing settings screen reachable from Account tab"
```

### Task 18: Customer custom-rate editing on New Pickup

**Files:**
- Modify: `lib/src/orders/new_pickup_screen.dart`
- Test: `test/orders/new_pickup_custom_rate_test.dart` (new)

> The only customer-write surface that exists. Add an optional "Custom rate (USh/kg)" field inside the existing collapsible "Add optional details" section. Blank → saves `null` (use default). A positive value → overrides. Validation rejects 0/negative. On submit, the field flows into the `Customer` written by `_onSubmit` and into the order's frozen snapshot.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:amuwak_staff/src/orders/new_pickup_screen.dart';
// reuse fakes from the new-pickup test harness; capture the upserted Customer

void main() {
  testWidgets('blank custom rate saves a null override', (tester) async {
    // pump NewPickupScreen, fill name/phone/address/service, leave custom rate blank
    // tap Create pickup
    // assert the captured Customer.customRatePerKgUgx is null
  });

  testWidgets('a positive custom rate is saved on the customer', (tester) async {
    // expand optional details, enter '4000' in Key('np_custom_rate')
    // submit; assert captured Customer.customRatePerKgUgx == 4000
    // and the order's ratePerKgSnapshotUgx == 4000
  });
}
```

> Use the same fake `CustomersRepository` from the existing new-pickup test that records `upsertCustomer(customer)` so the test can read back `customRatePerKgUgx`.

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/orders/new_pickup_custom_rate_test.dart`
Expected: FAIL — no custom-rate field.

- [ ] **Step 3: Add the field and wire it through**

In `lib/src/orders/new_pickup_screen.dart`:

Add a controller:
```dart
  final _customRateController = TextEditingController();
```

Inside the `if (_optionalExpanded) ...[` block (after the notes field), add:
```dart
              const SizedBox(height: 8),
              TextFormField(
                key: const Key('np_custom_rate'),
                controller: _customRateController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText:
                      'Custom rate (USh/kg) — blank = default of ${formatUgx(widget.defaultRatePerKgUgx.round())}',
                ),
              ),
```

In `_onSubmit`, parse it and apply to both the customer and the resolved rate:
```dart
    final customRateText = _customRateController.text.trim();
    final customRate =
        customRateText.isEmpty ? null : double.tryParse(customRateText);
    if (customRateText.isNotEmpty && (customRate == null || customRate <= 0)) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Custom rate must be greater than 0.')),
      );
      return;
    }
```
Set it on the `Customer(...)`:
```dart
      customRatePerKgUgx: customRate,
```
And override the snapshot resolution for the order (replace the `_resolvedRate` use in `_onSubmit`):
```dart
      ratePerKgSnapshotUgx: customRate ?? _resolvedRate,
```

Update the rate-display getter to reflect a typed custom rate live (optional polish): have `_resolvedRate` also consider `_customRateController`. Minimal version — leave the display tied to the matched customer/default; the snapshot uses the typed value at submit.

Dispose the controller:
```dart
    _customRateController.dispose();
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/orders/new_pickup_custom_rate_test.dart`
Expected: PASS.

- [ ] **Step 5: Run new-pickup regressions**

Run: `flutter test test/orders/`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/src/orders/new_pickup_screen.dart test/orders/new_pickup_custom_rate_test.dart
git commit -m "feat(orders): edit per-customer custom rate on New Pickup"
```

---

## Phase 7 — Full-suite verification

### Task 19: Green build + regression sweep

- [ ] **Step 1: Analyze**

Run: `flutter analyze`
Expected: no errors (warnings only if pre-existing).

- [ ] **Step 2: Full Dart/Flutter test run**

Run: `flutter test`
Expected: all tests pass.

- [ ] **Step 3: SQL test run**

Run: the pgTAP runner for `supabase/tests/0019_order_pricing_test.sql`.
Expected: all assertions pass.

- [ ] **Step 4: Manual smoke (optional but recommended)**

Use the `/run` skill or `flutter run` to walk: set a default rate in Account → Pricing settings → create a pickup (see the rate) → enter an estimate + a line item (see the provisional total) → open Order Details → enter final weight (badge clears, total recomputes) → confirm the total persisted after a reload.

- [ ] **Step 5: Commit any test fixups**

```bash
git add -A
git commit -m "test: stabilize pricing regression suite"
```

---

## Self-review notes (from plan author)

- **Spec coverage:** §3 pricing model → Task 4; §3.1 calc rules incl. half-up/clamp → Task 4; §3.2 frozen snapshot → Tasks 12, 14, 18; §4.1–4.4 schema/migration/tests → Tasks 1, 2; §5.1 pure module → Tasks 3–5; §5.2 LaundryOrder → Task 7; §5.3 repos → Tasks 11, 12; §5.4 UI table → Tasks 14 (New Pickup), 15 (Pickup Capture), 16 (Order Details, **subsumes the spec's IntakeScreen** — see Pre-flight #1), 17 (settings + Account), 18 (customer rate, via New Pickup — see Pre-flight #2); §5.5 formatUgx → Task 5; §6 data flow → Tasks 14→15→16; §7 edge cases (clamp, provisional fallback, snapshot immutability, legacy 0 rate) → covered by Tasks 4, 12, and the backfill in Task 1.
- **Deviations from spec (intentional, see Pre-flight):** (1) no standalone `IntakeScreen`; final weight is captured in Order Details. (2) custom-rate editing lives on New Pickup (no customer-edit screen exists). (3) `pricing_settings` is read one-shot, not via realtime.
- **Type consistency:** `recomputeTotal`/`PricingInputs`/`OrderTotal`/`LineItem`/`formatUgx` names are used identically across Tasks 4, 5, 12, 13, 15, 16. `OrdersRepository.recomputeOrderTotal`, `resolveRatePerKg`, and `updatePricing` are defined in Tasks 12/15 and reused in 16. `LaundryOrder.copyWith` gains `clearFinalWeight`/`clearEstimatedWeight` in Task 7 and they're used in Task 16.
- **Open implementer judgment calls flagged inline:** RLS policy wording in Task 1; `Object.hash` arg overflow in Task 7; `upsertOrder` vs new `updatePricing` in Task 15 (recommendation: use `updatePricing`); pgTAP seed rows in Task 2.
