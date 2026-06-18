-- 0024_gate_pricing_writes.sql
-- Restrict pricing WRITES to in_shop + manager across both pricing tables.
-- Reads stay open to all staff (drivers still need to see rates/fees/catalog at
-- pickup and billing). This supersedes the v1 "no role gate" on
-- pricing_settings_update (0019) and the driver-inclusive catalog write policies
-- (0022). Drivers become read-only for pricing.
--
-- DROP + CREATE (rather than ALTER POLICY) to match the house style in 0019/0022
-- and make the new role set explicit.

-- Global settings: writes -> in_shop, manager (SELECT policy unchanged).
DROP POLICY IF EXISTS pricing_settings_update ON pricing_settings;
CREATE POLICY pricing_settings_update ON pricing_settings FOR UPDATE
  USING      (auth_staff_role() IN ('in_shop', 'manager'))
  WITH CHECK (auth_staff_role() IN ('in_shop', 'manager'));

-- Catalog: writes -> in_shop, manager (SELECT policy unchanged).
DROP POLICY IF EXISTS pricing_catalog_items_insert ON pricing_catalog_items;
CREATE POLICY pricing_catalog_items_insert ON pricing_catalog_items FOR INSERT
  WITH CHECK (auth_staff_role() IN ('in_shop', 'manager'));

DROP POLICY IF EXISTS pricing_catalog_items_update ON pricing_catalog_items;
CREATE POLICY pricing_catalog_items_update ON pricing_catalog_items FOR UPDATE
  USING      (auth_staff_role() IN ('in_shop', 'manager'))
  WITH CHECK (auth_staff_role() IN ('in_shop', 'manager'));
