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
-- v1, per spec §2/§9). Follows the house style from 0007_rls.sql: role checks
-- are embedded in USING/WITH CHECK via auth_staff_role(); no `TO <role>` clause.
ALTER TABLE pricing_settings ENABLE ROW LEVEL SECURITY;

CREATE POLICY pricing_settings_read ON pricing_settings FOR SELECT
  USING (auth_staff_role() IN ('driver', 'in_shop', 'manager'));

CREATE POLICY pricing_settings_update ON pricing_settings FOR UPDATE
  USING      (auth_staff_role() IN ('driver', 'in_shop', 'manager'))
  WITH CHECK (auth_staff_role() IN ('driver', 'in_shop', 'manager'));

-- NB: pricing_settings is intentionally NOT added to supabase_realtime. The
-- settings screen reads it one-shot; orders carry their own frozen snapshot.
