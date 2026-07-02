-- 0040_create_pickup_rpc_test.sql
-- create_pickup() lets an active staff member atomically create a customer +
-- order with server-set attribution, and 0040 restores the least-privilege
-- driver role (reverting the 0039 remap).

BEGIN;
SET search_path TO extensions, public;

SELECT plan(10);

-- Seed a driver and an in_shop staff member (privileged session bypasses RLS).
INSERT INTO public.staff (id, username, display_name, role) VALUES
  ('00000000-0000-0000-0000-0000000000d1', 'drv_cp',  'D', 'driver'),
  ('00000000-0000-0000-0000-0000000000f1', 'shop_cp', 'S', 'in_shop');

-- ---- Act as the driver ----
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claim.sub" = '00000000-0000-0000-0000-0000000000d1';

-- 1. A driver can create a pickup through the RPC.
SELECT lives_ok($$
  SELECT create_pickup(
    '{"id":"00000000-0000-0000-0000-0000000000c1","name":"Jane","phone":"+256700111222"}'::jsonb,
    '{"id":"00000000-0000-0000-0000-0000000000a1","customer_name":"Jane","phone":"+256700111222","address":"Kampala","service_type":"wash_fold","item_count":3}'::jsonb
  )
$$, 'driver can create a pickup via create_pickup');

-- 2. The order is self-assigned to the driver.
SELECT is(
  (SELECT assigned_driver FROM orders WHERE id = '00000000-0000-0000-0000-0000000000a1'),
  '00000000-0000-0000-0000-0000000000d1'::uuid,
  'order.assigned_driver is the calling driver');

-- 3. Attribution + pinned status + a minted order code.
SELECT ok(
  (SELECT created_by = '00000000-0000-0000-0000-0000000000d1'::uuid
      AND intake_recorded_by = '00000000-0000-0000-0000-0000000000d1'::uuid
      AND status = 'pending_pickup'
      AND order_code LIKE 'AMW-%'
   FROM orders WHERE id = '00000000-0000-0000-0000-0000000000a1'),
  'order is attributed to the driver, pending_pickup, with a minted code');

-- 4. The customer row was created.
SELECT is(
  (SELECT name FROM customers WHERE id = '00000000-0000-0000-0000-0000000000c1'),
  'Jane', 'customer row created by the RPC');

-- 5. Idempotent: a retry with the same order id returns the existing code...
SELECT is(
  (SELECT create_pickup(
    '{"id":"00000000-0000-0000-0000-0000000000c1","name":"Jane","phone":"+256700111222"}'::jsonb,
    '{"id":"00000000-0000-0000-0000-0000000000a1","customer_name":"Jane","phone":"+256700111222","address":"Kampala","service_type":"wash_fold","item_count":3}'::jsonb
  )->>'order_code'),
  (SELECT order_code FROM orders WHERE id = '00000000-0000-0000-0000-0000000000a1'),
  'retry returns the existing order code');

-- 6. ...and does not duplicate the order.
SELECT is(
  (SELECT count(*)::int FROM orders WHERE id = '00000000-0000-0000-0000-0000000000a1'),
  1, 'retry does not create a duplicate order');

-- 7. A signed-in user with no staff row is rejected.
RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claim.sub" = '00000000-0000-0000-0000-0000000000e1';
SELECT throws_like($$
  SELECT create_pickup(
    '{"id":"00000000-0000-0000-0000-0000000000c9","name":"X","phone":"+256700000000"}'::jsonb,
    '{"id":"00000000-0000-0000-0000-0000000000a9","customer_name":"X","phone":"+256700000000","address":"A","service_type":"wash_fold","item_count":1}'::jsonb
  )
$$, '%active staff caller%', 'a non-staff caller is rejected');

-- 8. An in_shop caller creates an order with assigned_driver NULL (not self).
RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claim.sub" = '00000000-0000-0000-0000-0000000000f1';
SELECT lives_ok($$
  SELECT create_pickup(
    '{"id":"00000000-0000-0000-0000-0000000000c2","name":"Ann","phone":"+256701222333"}'::jsonb,
    '{"id":"00000000-0000-0000-0000-0000000000a2","customer_name":"Ann","phone":"+256701222333","address":"Ntinda","service_type":"wash_fold","item_count":2}'::jsonb
  )
$$, 'in_shop can create a pickup');
SELECT is(
  (SELECT assigned_driver FROM orders WHERE id = '00000000-0000-0000-0000-0000000000a2'),
  NULL::uuid, 'in_shop order is left unassigned (assigned_driver NULL)');

-- 9. Revert check: a driver still cannot write the customers table directly
-- (0039 remap is gone — driver is a driver again, not a manager).
RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claim.sub" = '00000000-0000-0000-0000-0000000000d1';
PREPARE direct_customer AS
  INSERT INTO public.customers (id, name, phone)
  VALUES ('00000000-0000-0000-0000-0000000000c3', 'Direct', '+256702000000');
SELECT throws_ok('direct_customer', '42501', NULL,
  'driver cannot write customers directly (0039 remap reverted)');

SELECT * FROM finish();
ROLLBACK;
