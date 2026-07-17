-- 0044_orders_customer_app_intake_test.sql
BEGIN;
SET search_path TO extensions, public;

SELECT plan(4);

SELECT has_column('public', 'orders', 'placed_by_customer_id',
  'orders.placed_by_customer_id exists');

-- sentinel staff row exists
SELECT is((SELECT display_name FROM staff
           WHERE id = '00000000-0000-0000-0000-00000000a001'),
          'Customer App', 'system sentinel staff row present');

-- transitions seeded for both fulfillment methods
SELECT is((SELECT count(*)::int FROM valid_transitions
           WHERE intake_method = 'customer_app'
             AND fulfillment_method = 'delivery'
             AND from_status IS NULL AND to_status = 'pending_pickup'),
          1, 'customer_app + delivery initial transition seeded');
SELECT is((SELECT count(*)::int FROM valid_transitions
           WHERE intake_method = 'customer_app'
             AND fulfillment_method = 'customer_collect'
             AND from_status = 'ready' AND to_status = 'completed'),
          1, 'customer_app + collect completion transition seeded');

SELECT * FROM finish();
ROLLBACK;
