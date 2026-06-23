-- 0026_pricing_catalog_item_category.sql
-- Adds an optional free-form category to managed service items so staff can
-- group the billing picker (e.g. "Dry Cleaning", "Bulky"). Nullable = no
-- category; existing rows backfill to NULL and behave exactly as before.
ALTER TABLE pricing_catalog_items
  ADD COLUMN category text;
