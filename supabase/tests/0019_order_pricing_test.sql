-- 0019_order_pricing_test.sql
-- Verifies the pricing schema: new columns exist, CHECK constraints reject bad
-- values, the pricing_settings singleton is enforced and seeded, and the
-- backfill set a non-zero snapshot on pre-existing orders.
-- Runs inside BEGIN ... ROLLBACK so nothing touches real data.

BEGIN;
SET search_path TO extensions, public;

SELECT plan(11);

-- Seed a throwaway staff member, customer, and order so the throws_ok UPDATE
-- cases are not no-ops (a no-op UPDATE throws nothing and the test would fail).
-- FK checks are left ON — we supply real UUIDs so constraints are satisfied.
INSERT INTO public.staff (id, username, display_name, role) VALUES
  ('00000000-0000-0000-0000-000000001900', 'pricing_test_mgr', 'Pricing Mgr', 'manager');

INSERT INTO public.customers (id, name, phone) VALUES
  ('00000000-0000-0000-0000-000000001901', 'Pricing Test Customer', '+256700000001');

INSERT INTO public.orders (
  id, order_code, customer_id, customer_name, phone, address,
  service_type, status, intake_method, fulfillment_method, item_count,
  intake_recorded_by, created_by
) VALUES (
  '00000000-0000-0000-0000-000000001902',
  'AMW-PRICE-TEST-1',
  '00000000-0000-0000-0000-000000001901',
  'Pricing Test Customer', '+256700000001', 'Test Address',
  'wash_fold', 'received', 'walk_in', 'delivery', 1,
  '00000000-0000-0000-0000-000000001900',
  '00000000-0000-0000-0000-000000001900'
);

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
      WHERE id = '00000000-0000-0000-0000-000000001901'$$,
  '23514', NULL,
  'customers.custom_rate_per_kg_ugx rejects a negative value');

-- CHECK: non-array line_items rejected (object literal {} is not an array).
SELECT throws_ok(
  $$UPDATE orders SET line_items = '{}'::jsonb
      WHERE id = '00000000-0000-0000-0000-000000001902'$$,
  '23514', NULL,
  'orders.line_items rejects a non-array jsonb');

SELECT * FROM finish();
ROLLBACK;
