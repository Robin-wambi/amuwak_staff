# Customer Order Pricing — Design Spec

**Date:** 2026-06-05
**Status:** Approved (design discussion); pending written-spec review
**Scope:** Add price-per-kg to customer orders with a global default rate, optional per-customer override, free-form line items, manual adjustments, and two-step weight capture (estimate at pickup, final at intake).
**Currency:** UGX (Ugandan Shillings), stored as integers.

---

## 1. Goals

1. Bill orders on weight × rate, with line items for special pieces (blankets, big jumpers, jackets, etc.) and an optional manual adjustment.
2. Capture an estimated weight + provisional total at pickup so the rider can quote the customer in person.
3. Capture a final weight at intake (shop) so billing uses the calibrated number.
4. Keep the per-order rate frozen at order creation so historical billing is stable when rates change.
5. Allow specific customers to have a negotiated rate that overrides the global default.

## 2. Non-goals (v1)

- Customer-facing notification (SMS / push) when final weight is recorded.
- Receipt generation (PDF, printable).
- Manual-adjustment reason / audit trail field.
- Discount or promo tracking separate from manual adjustment.
- Rate-change history / effective-date table.
- Revenue cards on the dashboard.
- Express / urgent pricing tiers.
- Multi-currency support.
- Role-based access (admin vs. driver vs. in-shop staff) for editing pricing.

## 3. Pricing model

- **One standard rate per kg** resolved per order from:
  - `customers.custom_rate_per_kg_ugx` if not null, **else**
  - `pricing_settings.default_rate_per_kg_ugx` (the singleton settings row).
- **Free-form line items** for special pieces. Each line item is `{ name: text, amount_ugx: integer ≥ 0 }`. Staff types both fields at the device.
- **Manual adjustment** is a single integer that can be negative (discount) or positive (surcharge).
- **No multi-category rates, no item catalog, no per-kg surcharges in v1.** All non-weight charges go through line items or manual adjustment.

### 3.1 Calculation rules

```
weight_to_bill     = COALESCE(final_weight_kg, estimated_weight_kg, 0)
weight_charge_ugx  = ROUND_HALF_UP(weight_to_bill * rate_per_kg_snapshot_ugx)   -- integer UGX
line_items_sum_ugx = SUM(line_items[].amount_ugx)
total_ugx          = MAX(0, weight_charge_ugx + line_items_sum_ugx + manual_adjustment_ugx)
```

Rules:
- Rounding uses **half-up** semantics (i.e. `(x + 0.5).floor()` for positive `x`), not banker's rounding, so the user-visible total matches a calculator the rider might run on their phone.
- Rounding happens **once on the weight charge**, not per line, to avoid drift.
- `total_ugx` is clamped at 0; the raw `manual_adjustment_ugx` is still stored so the original intent is recoverable.
- The order is **provisional** until `final_weight_kg` is non-null. Provisional totals are computed from the estimate and displayed with a `Provisional` badge.

### 3.2 Frozen rate snapshot

`orders.rate_per_kg_snapshot_ugx` is written **once at order creation** from the resolution rule in §3 and never overwritten. If the global default or the customer's custom rate changes later, this order continues to bill at its original rate. Future orders pick up the new rate.

## 4. Data model

All new columns follow existing repo conventions (snake_case, `*_ugx` suffix for currency, `*_kg` for weight, `*_at` for timestamps, soft delete via `deleted_at` only on tables that need it).

### 4.1 New columns on `customers`

```sql
ALTER TABLE customers
  ADD COLUMN custom_rate_per_kg_ugx numeric(10,2)
    CHECK (custom_rate_per_kg_ugx IS NULL OR custom_rate_per_kg_ugx > 0);
```

`NULL` means "use the global default." A positive value overrides it.

### 4.2 New columns on `orders`

```sql
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
```

Notes:
- `DEFAULT 0` on `rate_per_kg_snapshot_ugx` is only for the migration step (backfills existing rows). All new inserts MUST supply a real value; the Dart layer enforces this and a follow-up migration can tighten the constraint to `> 0` once backfill completes.
- `numeric(10,2)` for rate gives 10⁸ shilling precision — far more than needed; `numeric(6,2)` for weight allows up to 9,999.99 kg per order.
- `line_items` shape (validated in app code, not DB-side for v1):
  ```json
  [{ "name": "Blanket", "amount_ugx": 8000 },
   { "name": "Jacket",  "amount_ugx": 5000 }]
  ```

### 4.3 New table `pricing_settings`

Singleton table, one row, enforced via a partial unique index.

```sql
CREATE TABLE pricing_settings (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  default_rate_per_kg_ugx  numeric(10,2) NOT NULL CHECK (default_rate_per_kg_ugx > 0),
  updated_at               timestamptz NOT NULL DEFAULT now(),
  updated_by               uuid REFERENCES staff(id)
);

-- Enforce singleton: only one row allowed. No deleted_at column on this table
-- by design (a deleted settings row would leave the app with no rate to resolve).
CREATE UNIQUE INDEX pricing_settings_singleton ON pricing_settings ((true));

-- Seed initial value (placeholder; update via the in-app settings screen after deploy).
INSERT INTO pricing_settings (default_rate_per_kg_ugx) VALUES (5000.00);
```

### 4.4 Migration

New file: `supabase/migrations/0019_order_pricing.sql` — contains §4.1, §4.2, §4.3 in that order, plus a backfill for `rate_per_kg_snapshot_ugx` on existing `orders` rows using the seeded default. No changes to `valid_transitions`, RLS, or triggers — pricing fields don't participate in the state machine.

A matching test file `supabase/tests/0019_order_pricing_test.sql` covers:
- Singleton constraint on `pricing_settings`.
- `customers.custom_rate_per_kg_ugx` NULL vs. positive.
- Defaults applied to existing orders by the backfill.
- CHECK constraints reject negative weights, negative rates, non-array `line_items`.

## 5. App-layer changes

### 5.1 New pure module: `lib/src/orders/pricing/`

- `pricing_inputs.dart` — `PricingInputs` value type (rate, estimated/final weight, line items, manual adjustment).
- `pricing_calculator.dart` — `OrderTotal recomputeTotal(PricingInputs inputs)` returning `{ weightCharge, lineItemsSum, total, isProvisional }`. Pure function, no Riverpod, no I/O.
- `line_item.dart` — `LineItem` value type with validation (`amount_ugx >= 0`, name trimmed/non-empty).

This module has zero dependencies on Flutter or Supabase. Tests are pure Dart.

### 5.2 Changes to `LaundryOrder` (`lib/src/orders/order.dart`)

Add fields:
```dart
final double ratePerKgSnapshotUgx;       // required
final double? estimatedWeightKg;
final double? finalWeightKg;
final List<LineItem> lineItems;          // defaults to const []
final int manualAdjustmentUgx;           // defaults to 0
final int totalUgx;                      // defaults to 0
```

Update `fromDriftRow`, `fromSupabase`, `copyWith`, `==`, `hashCode` accordingly. `fromSupabase` reads `rate_per_kg_snapshot_ugx`, `estimated_weight_kg`, `final_weight_kg`, `line_items` (jsonb → `List<LineItem>`), `manual_adjustment_ugx`, `total_ugx`.

### 5.3 Repository wiring (`lib/src/orders/` + `lib/src/sync/repository_providers.dart`)

- `OrdersRepository.upsertOrder` — before any write, resolve `total_ugx` via `recomputeTotal(...)` and overwrite it. This is the single chokepoint that keeps the stored total consistent with its inputs.
- `OrdersRepository.create` (or whatever `NewPickupScreen` calls) — resolves `rate_per_kg_snapshot_ugx` from `customers.custom_rate_per_kg_ugx ?? pricing_settings.default_rate_per_kg_ugx` and writes it once.
- New `PricingSettingsRepository` for reading/writing `pricing_settings`. Exposes a single `defaultRatePerKgUgxProvider` (Riverpod) so the new-pickup flow and the settings screen share one source.

### 5.4 UI changes

| Screen | Change |
|---|---|
| `NewPickupScreen` | Small read-only line "Rate: USh X/kg" under the customer, recomputed live from the currently-selected customer's `custom_rate_per_kg_ugx ?? settings.default_rate_per_kg_ugx`. If the staff member swaps the customer, the displayed rate updates. The persisted `rate_per_kg_snapshot_ugx` is written from this resolved value at the moment of save. |
| `PickupCaptureScreen` | New "Pricing" section: `Estimated weight (kg)` numeric input, "+ Add item" sheet for free-form line items, live provisional total displayed prominently so the rider can read it to the customer. |
| `OrderDetailsScreen` | New editable Pricing block (visible once status > `pending_pickup`): final weight, line items (add/edit/remove), manual adjustment, read-only `Rate at order: USh X/kg`, computed total. Each save triggers `recomputeTotal` + repository write. |
| **New** `IntakeScreen` | Dedicated screen reached from `OrderDetailsScreen` via a "Record intake" CTA when status is `pending_pickup`. Big numeric input for `final_weight_kg`. On save: writes the weight, runs the `pending_pickup → received` transition, recomputes and persists `total_ugx`. |
| Customer edit screen | One optional field: `Custom rate (USh/kg) — blank = default of X`. Validates `> 0` when present. |
| Account tab | New "Pricing settings" entry → reads/writes the singleton `pricing_settings` row. No role check in v1; any signed-in staff member can change it. |

### 5.5 Display formatting

All UGX amounts use a single helper `formatUgx(int)` that returns `USh 8,000` style with thousands separators. Lives in `lib/src/shared/`. No decimal places shown.

## 6. Data flow

```
1. CREATE (NewPickupScreen)
   ├─ rate = customer.custom_rate_per_kg_ugx ?? settings.default
   ├─ rate_per_kg_snapshot_ugx = rate (frozen forever)
   ├─ estimated_weight_kg, final_weight_kg, line_items, manual_adjustment_ugx, total_ugx = defaults
   └─ status = pending_pickup

2. PICKUP (PickupCaptureScreen)
   ├─ rider enters estimated_weight_kg
   ├─ rider adds/edits line_items
   ├─ recomputeTotal runs locally on every change → provisional total shown on-screen for the customer
   └─ on save: estimated_weight_kg, line_items, total_ugx persisted (status stays pending_pickup until intake)

3. INTAKE (IntakeScreen)
   ├─ shop staff enters final_weight_kg
   ├─ recomputeTotal runs → total_ugx overwritten
   ├─ status transitions pending_pickup → received
   └─ pricing is no longer provisional

4. SUBSEQUENT EDITS (OrderDetailsScreen)
   ├─ any pricing field can be edited; recomputeTotal + persist on each save
   └─ rate_per_kg_snapshot_ugx remains immutable
```

## 7. Edge cases

| Case | Behavior |
|---|---|
| Order has estimate but no final weight at intake or later | Bills on estimate as fallback; `Provisional` badge visible. |
| Final weight much higher than estimate | No warning in v1 (deferred). |
| Order cancelled after pickup | Pricing fields preserved for audit. `total_ugx` reported separately or excluded by status filter as needed. |
| Customer's custom rate or global default changed after order is created | No effect on this order (snapshot frozen). Future orders use the new value. |
| Line item amount entered as negative | Input validation rejects; discounts must go through `manual_adjustment_ugx`. |
| `manual_adjustment_ugx` would make total negative | `total_ugx` clamped at 0; raw `manual_adjustment_ugx` still stored. |
| `rate_per_kg_snapshot_ugx` is 0 (legacy backfill) | UI shows the order with `0` rate; staff can edit it via `OrderDetailsScreen` only if explicitly enabled. For v1 we **do not** allow editing the snapshot rate — fix at the SQL level if needed. |
| `pricing_settings` returns 0 rows on read (corrupted state) | Repository throws; UI shows error "Pricing settings missing — contact admin." Singleton index should prevent this. |
| Migration runs on a DB with existing orders | Backfill writes seeded default into `rate_per_kg_snapshot_ugx`; weights stay null, `total_ugx` stays 0 until staff records them. |

## 8. Testing

### 8.1 Pure Dart
- `recomputeTotal` exhaustive cases: zero weight, only line items, only manual adjustment, negative adjustment clamped at 0, rounding at 0.5, large amounts.
- `LineItem` validation: empty name rejected, negative amount rejected, whitespace-only name rejected.
- `PricingInputs` round-trip: from order → inputs → `recomputeTotal` → back to order is stable.

### 8.2 Repository
- `OrdersRepository.upsertOrder` always recomputes `total_ugx` before write — assert by writing a deliberately-stale total and reading back the corrected one.
- `OrdersRepository.create` resolves rate from customer override when present, else from settings.

### 8.3 Widget
- `NewPickupScreen` displays the resolved rate.
- `PickupCaptureScreen` live total updates as weight/line items change.
- `IntakeScreen` recomputes and persists total; status transitions on save.
- Customer edit screen accepts blank custom rate (saves NULL) and rejects 0 / negative.
- Pricing settings screen reads, edits, and persists the singleton row.

### 8.4 Integration
- Full flow: create → pickup (estimate + line items) → intake (final weight) → completed. Assert stored `total_ugx` matches the displayed total at every step and matches the calculated value from `recomputeTotal`.

### 8.5 SQL
- `supabase/tests/0019_order_pricing_test.sql` as described in §4.4.

## 9. Risks

1. **Backfilled `rate_per_kg_snapshot_ugx = 0` on legacy orders.** Mitigation: the v1 UI surfaces these as `USh 0/kg` so they're obvious; staff can re-create or annotate them.
2. **Free-form line items prevent item-level reporting.** Accepted trade-off; revisit when a stable catalog emerges.
3. **No role check on pricing settings.** Any signed-in staff can change the global default. Accepted for v1; revisit when role-based UI exists.
4. **No dispute audit trail.** Customers can only verify by being present at pickup (the rider shows them the device). When this becomes a problem we add `manual_adjustment_reason` and customer notifications.

## 10. Open questions

None at design time — all clarifications resolved during brainstorming. New questions go to the implementation plan or a follow-up spec.
