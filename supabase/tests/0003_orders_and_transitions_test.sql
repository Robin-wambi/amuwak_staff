-- 0003_orders_and_transitions_test.sql
-- Verify orders schema, the intake/fulfillment CHECKs, and the valid_transitions
-- seed.

BEGIN;
SET search_path TO extensions, public;

SELECT plan(11);

SELECT has_table('public', 'orders', 'orders table exists');
SELECT has_column('public', 'orders', 'order_code', 'orders.order_code exists');
SELECT col_is_unique('public', 'orders', ARRAY['order_code'], 'orders.order_code is unique');
SELECT has_column('public', 'orders', 'intake_method', 'orders.intake_method exists');
SELECT has_column('public', 'orders', 'fulfillment_method', 'orders.fulfillment_method exists');
SELECT col_has_check('public', 'orders', 'intake_method', 'orders.intake_method has CHECK');
SELECT col_has_check('public', 'orders', 'fulfillment_method', 'orders.fulfillment_method has CHECK');

SELECT has_table('public', 'valid_transitions', 'valid_transitions table exists');

-- Row counts:
--   walk_in/customer_collect      = 4
--   walk_in/delivery              = 5
--   driver_pickup/customer_collect = 5
--   driver_pickup/delivery        = 6
--   phone_order (copy of driver_pickup variants) = 5 + 6 = 11
--   customer_app (copy of driver_pickup variants, added in 0044) = 5 + 6 = 11
--   Total = 42
SELECT is((SELECT count(*) FROM public.valid_transitions)::int, 42,
  'valid_transitions seeded with all intake/fulfillment/status combinations');

SELECT is(
  (SELECT count(*) FROM public.valid_transitions
   WHERE intake_method = 'walk_in'
     AND fulfillment_method = 'customer_collect'
     AND from_status IS NULL
     AND to_status = 'received')::int,
  1, 'walk_in/customer_collect can start at received');

SELECT is(
  (SELECT count(*) FROM public.valid_transitions
   WHERE from_status = 'pending_pickup'
     AND to_status = 'completed')::int,
  0, 'cannot jump from pending_pickup straight to completed');

SELECT * FROM finish();
ROLLBACK;
