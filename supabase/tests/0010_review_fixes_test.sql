-- 0010_review_fixes_test.sql
-- Verify the four fixes from the post-implementation code review:
--   * orders_update WITH CHECK prevents driver reassigning their own order
--   * orders_insert pins initial status by intake_method
--   * orders.assigned_driver must reference a staff row with role=driver
--   * validate_status_transition rejects stale from_status
--   * cross-table FKs are DEFERRABLE INITIALLY DEFERRED

BEGIN;
SET search_path TO extensions, public;

SELECT plan(6);

-- Seed two drivers, one in_shop, one manager
INSERT INTO public.staff (id, username, display_name, role) VALUES
  ('00000000-0000-0000-0000-000000000301', 'd1_review', 'D1', 'driver'),
  ('00000000-0000-0000-0000-000000000302', 'd2_review', 'D2', 'driver'),
  ('00000000-0000-0000-0000-000000000303', 'shop_review', 'S',  'in_shop'),
  ('00000000-0000-0000-0000-000000000304', 'mgr_review',  'M',  'manager');

-- Seed an order assigned to driver1 (privileged insert bypasses RLS via psql session role)
INSERT INTO public.orders (
  id, order_code, customer_name, phone, address, service_type, status,
  intake_method, fulfillment_method, item_count,
  assigned_driver, intake_recorded_by, created_by
) VALUES (
  '00000000-0000-0000-0000-000000000401', 'AMW-REV-1', 'C', '+254', 'A',
  'wash_fold', 'pending_pickup', 'driver_pickup', 'delivery', 3,
  '00000000-0000-0000-0000-000000000301',
  '00000000-0000-0000-0000-000000000301',
  '00000000-0000-0000-0000-000000000301'
);

-- 1. Driver cannot reassign their own order to driver2 (WITH CHECK)
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claim.sub" = '00000000-0000-0000-0000-000000000301';

PREPARE bad_reassign AS
  UPDATE public.orders
     SET assigned_driver = '00000000-0000-0000-0000-000000000302'
   WHERE id = '00000000-0000-0000-0000-000000000401';
SELECT throws_ok('bad_reassign', '42501',
  NULL, 'driver cannot reassign their own order to another driver');

-- 2. Driver cannot INSERT an order at status='completed'
PREPARE bad_initial_status AS
  INSERT INTO public.orders (
    id, order_code, customer_name, phone, address, service_type, status,
    intake_method, fulfillment_method, item_count,
    assigned_driver, intake_recorded_by, created_by
  ) VALUES (
    gen_random_uuid(), 'AMW-REV-BAD', 'C', '+254', 'A',
    'wash_fold', 'completed', 'driver_pickup', 'delivery', 3,
    '00000000-0000-0000-0000-000000000301',
    '00000000-0000-0000-0000-000000000301',
    '00000000-0000-0000-0000-000000000301'
  );
SELECT throws_ok('bad_initial_status', '42501',
  NULL, 'driver cannot insert an order at status=completed');

-- 3. assigned_driver pointing at a manager is rejected by the trigger
RESET ROLE;
PREPARE bad_assigned_role AS
  UPDATE public.orders
     SET assigned_driver = '00000000-0000-0000-0000-000000000304'  -- manager UUID
   WHERE id = '00000000-0000-0000-0000-000000000401';
SELECT throws_like('bad_assigned_role',
  '%must reference an active staff row with role=driver%',
  'assigned_driver pointing at a non-driver is rejected');

-- 4. validate_status_transition rejects a stale from_status.
-- Advance the order to 'received' first as a privileged role.
INSERT INTO public.order_status_events (order_id, from_status, to_status, changed_by, source)
VALUES ('00000000-0000-0000-0000-000000000401', 'pending_pickup', 'received',
        '00000000-0000-0000-0000-000000000301', 'manual');

PREPARE stale_transition AS
  INSERT INTO public.order_status_events (order_id, from_status, to_status, changed_by, source)
  VALUES ('00000000-0000-0000-0000-000000000401',
          'pending_pickup',   -- stale; current status is now 'received'
          'received',
          '00000000-0000-0000-0000-000000000301', 'manual');
SELECT throws_like('stale_transition', '%stale transition%',
  'stale from_status (not matching orders.status) is rejected');

-- 5. Cross-table FK is DEFERRABLE INITIALLY DEFERRED
SELECT is(
  (SELECT condeferrable AND condeferred FROM pg_constraint
   WHERE conname = 'order_status_events_order_id_fkey'),
  true,
  'order_status_events.order_id FK is DEFERRABLE INITIALLY DEFERRED');

SELECT is(
  (SELECT condeferrable AND condeferred FROM pg_constraint
   WHERE conname = 'proof_photos_proof_event_id_fkey'),
  true,
  'proof_photos.proof_event_id FK is DEFERRABLE INITIALLY DEFERRED');

SELECT * FROM finish();
ROLLBACK;
