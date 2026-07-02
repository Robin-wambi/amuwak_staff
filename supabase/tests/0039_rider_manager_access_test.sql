-- 0039_rider_manager_access_test.sql
-- A rider (role='driver') now has manager parity (migration 0039 remaps
-- 'driver' -> 'manager' in auth_staff_role()): it can write customers, create
-- orders without self-assigning a driver, and read every order.

BEGIN;
SET search_path TO extensions, public;

SELECT plan(4);

-- Seed two riders. Privileged session role, so these inserts bypass RLS.
INSERT INTO public.staff (id, username, display_name, role) VALUES
  ('00000000-0000-0000-0000-000000000901', 'rider1_0039', 'R1', 'driver'),
  ('00000000-0000-0000-0000-000000000902', 'rider2_0039', 'R2', 'driver');

-- An order owned entirely by rider2, to prove rider1 can now see it.
INSERT INTO public.orders (
  id, order_code, customer_name, phone, address, service_type, status,
  intake_method, fulfillment_method, item_count,
  assigned_driver, intake_recorded_by, created_by
) VALUES (
  '00000000-0000-0000-0000-000000000a02', 'AMW-0039-2', 'C2', '+256', 'A',
  'wash_fold', 'pending_pickup', 'driver_pickup', 'delivery', 3,
  '00000000-0000-0000-0000-000000000902',
  '00000000-0000-0000-0000-000000000902',
  '00000000-0000-0000-0000-000000000902'
);

-- ---- Act as rider1 ----
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claim.sub" = '00000000-0000-0000-0000-000000000901';

-- 1. Rider can write customers (customers_write was in_shop/manager only).
PREPARE write_customer AS
  INSERT INTO public.customers (id, name, phone)
  VALUES ('00000000-0000-0000-0000-000000000c01', 'New Cust', '+256700000000');
SELECT lives_ok('write_customer',
  'rider can insert a customer (manager parity)');

-- 2. Rider can create a driver_pickup order WITHOUT setting assigned_driver
--    (manager insert branch needs only created_by + a status pinned to the
--    intake method).
PREPARE create_order AS
  INSERT INTO public.orders (
    id, order_code, customer_name, phone, address, service_type, status,
    intake_method, fulfillment_method, item_count,
    intake_recorded_by, created_by
  ) VALUES (
    '00000000-0000-0000-0000-000000000a01', 'AMW-0039-1', 'C1', '+256', 'A',
    'wash_fold', 'pending_pickup', 'driver_pickup', 'delivery', 3,
    '00000000-0000-0000-0000-000000000901',
    '00000000-0000-0000-0000-000000000901'
  );
SELECT lives_ok('create_order',
  'rider can create a pickup without self-assigning (manager parity)');

-- 3. Rider sees ALL orders, including rider2's (manager read = true).
SELECT is(
  (SELECT count(*) FROM public.orders
   WHERE id IN ('00000000-0000-0000-0000-000000000a01',
                '00000000-0000-0000-0000-000000000a02'))::int,
  2, 'rider sees all orders, not just their own (manager parity)');

-- 4. The order the rider created is attributed to them.
SELECT is(
  (SELECT created_by FROM public.orders
   WHERE id = '00000000-0000-0000-0000-000000000a01'),
  '00000000-0000-0000-0000-000000000901'::uuid,
  'created order is attributed to the rider');

SELECT * FROM finish();
ROLLBACK;
