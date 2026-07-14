-- 0046_customer_rls_test.sql
BEGIN;
SET search_path TO extensions, public;

SELECT plan(7);

-- Two customers, each linked to an auth user.
INSERT INTO public.customers (id, name, phone, auth_user_id) VALUES
  ('00000000-0000-0000-0000-00000000c101', 'Cust1', '0700000101',
   '00000000-0000-0000-0000-00000000a101'),
  ('00000000-0000-0000-0000-00000000c102', 'Cust2', '0700000102',
   '00000000-0000-0000-0000-00000000a102');

-- An order belonging to Cust1 (inserted privileged, sentinel staff attribution).
INSERT INTO public.staff (id, username, display_name, role, active) VALUES
  ('00000000-0000-0000-0000-00000000a001', 'system_customer_app',
   'Customer App', 'in_shop', false)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.orders (
  id, order_code, customer_id, placed_by_customer_id, customer_name, phone,
  address, service_type, status, intake_method, fulfillment_method, item_count,
  intake_recorded_by, created_by
) VALUES (
  '00000000-0000-0000-0000-00000000o101', 'AMW-CUST-1',
  '00000000-0000-0000-0000-00000000c101', '00000000-0000-0000-0000-00000000c101',
  'Cust1', '0700000101', 'Addr', 'wash_fold', 'pending_pickup',
  'customer_app', 'delivery', 3,
  '00000000-0000-0000-0000-00000000a001', '00000000-0000-0000-0000-00000000a001');

-- ---- Cust1 sees their own order ----
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claim.sub" = '00000000-0000-0000-0000-00000000a101';
SELECT is((SELECT count(*)::int FROM orders
           WHERE id = '00000000-0000-0000-0000-00000000o101'),
          1, 'Cust1 sees their own order');

-- Cust1 can place a self-attributed customer_app order.
PREPARE place_ok AS
  INSERT INTO orders (
    order_code, customer_id, placed_by_customer_id, customer_name, phone,
    address, service_type, status, intake_method, fulfillment_method, item_count,
    intake_recorded_by, created_by
  ) VALUES (
    'AMW-CUST-NEW', '00000000-0000-0000-0000-00000000c101',
    '00000000-0000-0000-0000-00000000c101', 'Cust1', '0700000101', 'Addr',
    'wash_fold', 'pending_pickup', 'customer_app', 'delivery', 2,
    '00000000-0000-0000-0000-00000000a001', '00000000-0000-0000-0000-00000000a001');
SELECT lives_ok('place_ok', 'Cust1 can place a self-attributed customer_app order');

-- Cust1 cannot place an order attributed to Cust2.
PREPARE place_forge AS
  INSERT INTO orders (
    order_code, customer_id, placed_by_customer_id, customer_name, phone,
    address, service_type, status, intake_method, fulfillment_method, item_count,
    intake_recorded_by, created_by
  ) VALUES (
    'AMW-CUST-FORGE', '00000000-0000-0000-0000-00000000c102',
    '00000000-0000-0000-0000-00000000c102', 'Cust2', '0700000102', 'Addr',
    'wash_fold', 'pending_pickup', 'customer_app', 'delivery', 2,
    '00000000-0000-0000-0000-00000000a001', '00000000-0000-0000-0000-00000000a001');
SELECT throws_ok('place_forge', '42501', NULL,
  'Cust1 cannot place an order for Cust2');

-- Cust1 cannot advance status (no UPDATE policy).
PREPARE bump AS
  UPDATE orders SET status = 'received'
   WHERE id = '00000000-0000-0000-0000-00000000o101';
SELECT throws_ok('bump', '42501', NULL, 'Cust1 cannot advance order status');

-- ---- Cust2 is denied Cust1's order (the critical cross-customer test) ----
RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claim.sub" = '00000000-0000-0000-0000-00000000a102';
SELECT is((SELECT count(*)::int FROM orders
           WHERE id = '00000000-0000-0000-0000-00000000o101'),
          0, 'Cust2 cannot see Cust1 order');

-- Cust2 cannot message Cust1's order.
PREPARE msg_forge AS
  INSERT INTO order_messages (order_id, sender_kind, sender_id, body)
  VALUES ('00000000-0000-0000-0000-00000000o101', 'customer',
          '00000000-0000-0000-0000-00000000c102', 'hi');
SELECT throws_ok('msg_forge', '42501', NULL,
  'Cust2 cannot message Cust1 order');

-- ---- Cust1 can message their own order ----
RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claim.sub" = '00000000-0000-0000-0000-00000000a101';
PREPARE msg_ok AS
  INSERT INTO order_messages (order_id, sender_kind, sender_id, body)
  VALUES ('00000000-0000-0000-0000-00000000o101', 'customer',
          '00000000-0000-0000-0000-00000000c101', 'hello');
SELECT lives_ok('msg_ok', 'Cust1 can message their own order');

SELECT * FROM finish();
ROLLBACK;
