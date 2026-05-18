-- 0005_triggers_test.sql
-- Verify the updated_at and status-transition triggers.

BEGIN;
SET search_path TO extensions, public;

SELECT plan(5);

-- Seed a manager + a walk_in/delivery order at status='received'
INSERT INTO public.staff (id, username, display_name, role) VALUES
  ('00000000-0000-0000-0000-000000000010', 'mgr_trig_test', 'Mgr Trig', 'manager');

INSERT INTO public.orders (
  id, order_code, customer_name, phone, address, service_type, status,
  intake_method, fulfillment_method, item_count,
  intake_recorded_by, created_by
) VALUES (
  '00000000-0000-0000-0000-000000000100', 'AMW-TRIG-1', 'Cust', '+254700', 'Addr',
  'wash_fold', 'received', 'walk_in', 'delivery', 5,
  '00000000-0000-0000-0000-000000000010', '00000000-0000-0000-0000-000000000010'
);

-- updated_at advances when we UPDATE
SELECT lives_ok(
  $$UPDATE public.orders
    SET notes = 'updated by trigger test'
    WHERE id = '00000000-0000-0000-0000-000000000100'$$,
  'orders UPDATE succeeds'
);
SELECT cmp_ok(
  (SELECT updated_at FROM public.orders
   WHERE id = '00000000-0000-0000-0000-000000000100'),
  '>',
  (SELECT created_at FROM public.orders
   WHERE id = '00000000-0000-0000-0000-000000000100'),
  'updated_at advances past created_at after UPDATE'
);

-- Legal transition: received -> in_progress for walk_in/delivery
SELECT lives_ok(
  $$INSERT INTO public.order_status_events (order_id, from_status, to_status, changed_by, source)
    VALUES ('00000000-0000-0000-0000-000000000100',
            'received', 'in_progress',
            '00000000-0000-0000-0000-000000000010',
            'manual')$$,
  'legal status transition accepted'
);

-- Trigger mirrored the new status onto orders.status
SELECT is(
  (SELECT status FROM public.orders
   WHERE id = '00000000-0000-0000-0000-000000000100'),
  'in_progress',
  'orders.status mirrored by trigger after legal transition'
);

-- Illegal jump: in_progress -> completed (skips ready + out_for_delivery)
PREPARE bad_jump AS
  INSERT INTO public.order_status_events (order_id, from_status, to_status, changed_by, source)
  VALUES ('00000000-0000-0000-0000-000000000100',
          'in_progress', 'completed',
          '00000000-0000-0000-0000-000000000010',
          'manual');
SELECT throws_like('bad_jump', '%illegal status transition%',
  'illegal status transition rejected');

SELECT * FROM finish();
ROLLBACK;
