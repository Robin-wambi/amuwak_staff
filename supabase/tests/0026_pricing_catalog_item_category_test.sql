-- 0026_pricing_catalog_item_category_test.sql
-- Verifies 0026 added the optional grouping column pricing_catalog_items.category
-- as a nullable TEXT: existing rows stay valid with no category, and a row can be
-- inserted without supplying one. Runs inside BEGIN ... ROLLBACK so nothing
-- touches real data.

BEGIN;
SET search_path TO extensions, public;

SELECT plan(3);

SELECT has_column('public', 'pricing_catalog_items', 'category',
  'pricing_catalog_items.category exists');

SELECT col_type_is('public', 'pricing_catalog_items', 'category', 'text',
  'pricing_catalog_items.category is text');

SELECT col_is_null('public', 'pricing_catalog_items', 'category',
  'pricing_catalog_items.category is nullable (rows without a category stay valid)');

SELECT * FROM finish();
ROLLBACK;
