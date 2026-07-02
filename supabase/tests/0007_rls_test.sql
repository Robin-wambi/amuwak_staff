-- 0007_rls_test.sql
-- Exercise RLS policies for the driver / in_shop / manager roles.
--
-- We don't insert into auth.users — staff.id has no FK to it. RLS reads
-- auth.uid() via the JWT sub claim, which we set explicitly per test.

BEGIN;
SET search_path TO extensions, public;

SELECT plan(5);

-- Seed three staff: two drivers and one in-shop user
INSERT INTO public.staff (id, username, display_name, role) VALUES
  ('00000000-0000-0000-0000-000000000001', 'driver1_rls', 'D1', 'driver'),
  ('00000000-0000-0000-0000-000000000002', 'shop1_rls',   'S1', 'in_shop'),
  ('00000000-0000-0000-0000-000000000003', 'driver2_rls', 'D2', 'driver');

-- Seed two orders, one assigned to each driver, as the privileged role
INSERT INTO public.orders (
  id, order_code, customer_name, phone, address, service_type, status,
  intake_method, fulfillment_method, item_count,
  assigned_driver, intake_recorded_by, created_by
) VALUES
  ('00000000-0000-0000-0000-000000000201', 'AMW-RLS-1', 'C1', '+254', 'A',
   'wash_fold', 'pending_pickup', 'driver_pickup', 'delivery', 3,
   '00000000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-000000000001'),
  ('00000000-0000-0000-0000-000000000202', 'AMW-RLS-2', 'C2', '+254', 'A',
   'wash_fold', 'pending_pickup', 'driver_pickup', 'delivery', 3,
   '00000000-0000-0000-0000-000000000003',
   '00000000-0000-0000-0000-000000000003',
   '00000000-0000-0000-0000-000000000003');

-- ---- Driver 1's view ----
-- Since 0039 (rider_manager_access) collapses 'driver' -> 'manager' in
-- auth_staff_role(), a driver now has manager parity: it reads every order, not
-- just its own assigned/unassigned ones. These two assertions assert that
-- elevated behaviour (they asserted the old driver-only scoping before 0039).
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claim.sub" = '00000000-0000-0000-0000-000000000001';

SELECT is(
  (SELECT count(*) FROM public.orders
   WHERE id IN ('00000000-0000-0000-0000-000000000201',
                '00000000-0000-0000-0000-000000000202'))::int,
  2, 'driver1 (manager parity, 0039) sees all orders');

SELECT is(
  (SELECT count(*) FROM public.orders
   WHERE id = '00000000-0000-0000-0000-000000000202')::int,
  1, 'driver1 (manager parity, 0039) sees driver2''s order too');

-- driver1 can now read driver2's status events (none seeded, so still 0, but
-- the manager-parity read policy would permit them).
SELECT is(
  (SELECT count(*) FROM public.order_status_events
   WHERE order_id = '00000000-0000-0000-0000-000000000202')::int,
  0, 'no driver2 status events were seeded');

-- ---- In-shop staff view ----
RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claim.sub" = '00000000-0000-0000-0000-000000000002';

SELECT is(
  (SELECT count(*) FROM public.orders
   WHERE id IN ('00000000-0000-0000-0000-000000000201',
                '00000000-0000-0000-0000-000000000202'))::int,
  2, 'in_shop sees both orders');

-- ---- Forgery rejected ----
RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claim.sub" = '00000000-0000-0000-0000-000000000001';

PREPARE forge AS
  INSERT INTO public.proof_events
    (order_id, type, captured_at, item_count, captured_by)
  VALUES
    ('00000000-0000-0000-0000-000000000201', 'pickup', now(), 3,
     '00000000-0000-0000-0000-000000000003');  -- attempts to attribute to driver2
SELECT throws_ok('forge', '42501',
  NULL, 'driver1 cannot insert a proof event attributed to driver2');

SELECT * FROM finish();
ROLLBACK;
