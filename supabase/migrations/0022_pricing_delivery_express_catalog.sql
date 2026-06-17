-- 0022_pricing_delivery_express_catalog.sql
-- Extends pricing with a flat delivery fee and an express/turnaround surcharge
-- (flat + percentage), plus a managed catalog of priced service items.
--
-- Settings hold the global config; each order freezes the values in force at
-- creation (mirroring rate_per_kg_snapshot_ugx) so the bill recomputes correctly
-- when the final weight is recorded. The express percentage is applied in the
-- Dart calculator on weight charge + line items only.
-- See docs/superpowers/plans (pricing delivery/express/catalog).

-- 1. Global config on the singleton settings row. Defaults 0 = feature off until
--    staff set values via the settings screen.
ALTER TABLE pricing_settings
  ADD COLUMN delivery_fee_ugx integer NOT NULL DEFAULT 0
    CHECK (delivery_fee_ugx >= 0),
  ADD COLUMN express_surcharge_flat_ugx integer NOT NULL DEFAULT 0
    CHECK (express_surcharge_flat_ugx >= 0),
  ADD COLUMN express_surcharge_pct numeric(5,2) NOT NULL DEFAULT 0
    CHECK (express_surcharge_pct >= 0);

-- 2. Per-order frozen snapshots. DEFAULT 0/false also backfills existing orders,
--    which then bill exactly as before (no delivery, not express).
ALTER TABLE orders
  ADD COLUMN delivery_fee_snapshot_ugx integer NOT NULL DEFAULT 0
    CHECK (delivery_fee_snapshot_ugx >= 0),
  ADD COLUMN is_express boolean NOT NULL DEFAULT false,
  ADD COLUMN express_flat_snapshot_ugx integer NOT NULL DEFAULT 0
    CHECK (express_flat_snapshot_ugx >= 0),
  ADD COLUMN express_pct_snapshot numeric(5,2) NOT NULL DEFAULT 0
    CHECK (express_pct_snapshot >= 0);

-- 3. Managed service item catalog. Retired items keep active = false (hidden from
--    the picker, preserved for history) rather than being deleted.
CREATE TABLE pricing_catalog_items (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name       text NOT NULL CHECK (length(btrim(name)) > 0),
  amount_ugx integer NOT NULL CHECK (amount_ugx >= 0),
  active     boolean NOT NULL DEFAULT true,
  sort_order integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- RLS mirrors pricing_settings (0019): role checks embedded in USING/WITH CHECK
-- via auth_staff_role(); no `TO <role>` clause. No role gate beyond staff in v1.
ALTER TABLE pricing_catalog_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY pricing_catalog_items_read ON pricing_catalog_items FOR SELECT
  USING (auth_staff_role() IN ('driver', 'in_shop', 'manager'));

CREATE POLICY pricing_catalog_items_insert ON pricing_catalog_items FOR INSERT
  WITH CHECK (auth_staff_role() IN ('driver', 'in_shop', 'manager'));

CREATE POLICY pricing_catalog_items_update ON pricing_catalog_items FOR UPDATE
  USING      (auth_staff_role() IN ('driver', 'in_shop', 'manager'))
  WITH CHECK (auth_staff_role() IN ('driver', 'in_shop', 'manager'));

-- NB: pricing_catalog_items is intentionally NOT added to supabase_realtime. The
-- catalog is read one-shot (like pricing_settings) and refetched after edits.
