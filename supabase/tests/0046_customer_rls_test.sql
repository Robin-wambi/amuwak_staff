-- 0046_customer_rls_test.sql
BEGIN;
SET search_path TO extensions, public;

SELECT plan(11);

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
  '00000000-0000-0000-0000-00000000b101', 'AMW-CUST-1',
  '00000000-0000-0000-0000-00000000c101', '00000000-0000-0000-0000-00000000c101',
  'Cust1', '0700000101', 'Addr', 'wash_fold', 'pending_pickup',
  'customer_app', 'delivery', 3,
  '00000000-0000-0000-0000-00000000a001', '00000000-0000-0000-0000-00000000a001');

-- ---- Cust1 sees their own order ----
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claim.sub" = '00000000-0000-0000-0000-00000000a101';
SELECT is((SELECT count(*)::int FROM orders
           WHERE id = '00000000-0000-0000-0000-00000000b101'),
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

-- Cust1 cannot advance status: there is no customer UPDATE policy on orders, so
-- under RLS the UPDATE matches zero rows (a silent no-op) rather than raising.
-- Assert the security property that matters — the status is left unchanged.
UPDATE orders SET status = 'received'
 WHERE id = '00000000-0000-0000-0000-00000000b101';
SELECT is((SELECT status FROM orders
           WHERE id = '00000000-0000-0000-0000-00000000b101'),
          'pending_pickup', 'Cust1 cannot advance order status (no-op under RLS)');

-- ---- Cust2 is denied Cust1's order (the critical cross-customer test) ----
RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claim.sub" = '00000000-0000-0000-0000-00000000a102';
SELECT is((SELECT count(*)::int FROM orders
           WHERE id = '00000000-0000-0000-0000-00000000b101'),
          0, 'Cust2 cannot see Cust1 order');

-- Cust2 cannot message Cust1's order.
PREPARE msg_forge AS
  INSERT INTO order_messages (order_id, sender_kind, sender_id, body)
  VALUES ('00000000-0000-0000-0000-00000000b101', 'customer',
          '00000000-0000-0000-0000-00000000c102', 'hi');
SELECT throws_ok('msg_forge', '42501', NULL,
  'Cust2 cannot message Cust1 order');

-- ---- Cust1 can message their own order ----
RESET ROLE;
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claim.sub" = '00000000-0000-0000-0000-00000000a101';
PREPARE msg_ok AS
  INSERT INTO order_messages (order_id, sender_kind, sender_id, body)
  VALUES ('00000000-0000-0000-0000-00000000b101', 'customer',
          '00000000-0000-0000-0000-00000000c101', 'hello');
SELECT lives_ok('msg_ok', 'Cust1 can message their own order');

-- ---- A customer may mark a staff reply read, but never rewrite it ----
-- order_messages_mark_read makes this row updatable by Cust1, but RLS is
-- row-level only; the column grant in 0046 is what stops the tampering.
RESET ROLE;
INSERT INTO public.order_messages (id, order_id, sender_kind, sender_id, body)
VALUES ('00000000-0000-0000-0000-00000000f101',
        '00000000-0000-0000-0000-00000000b101', 'staff',
        '00000000-0000-0000-0000-00000000a001', 'Your order is on the way');

SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claim.sub" = '00000000-0000-0000-0000-00000000a101';

PREPARE tamper_body AS
  UPDATE order_messages SET body = 'Pay 0700000999 instead'
   WHERE id = '00000000-0000-0000-0000-00000000f101';
SELECT throws_ok('tamper_body', '42501', NULL,
  'Cust1 cannot rewrite a staff reply body');

PREPARE tamper_sender AS
  UPDATE order_messages SET sender_kind = 'customer'
   WHERE id = '00000000-0000-0000-0000-00000000f101';
SELECT throws_ok('tamper_sender', '42501', NULL,
  'Cust1 cannot forge message attribution');

PREPARE mark_read AS
  UPDATE order_messages SET read_at = now()
   WHERE id = '00000000-0000-0000-0000-00000000f101';
SELECT lives_ok('mark_read', 'Cust1 can still mark a staff reply read');

RESET ROLE;
SELECT is(
  (SELECT body FROM order_messages
    WHERE id = '00000000-0000-0000-0000-00000000f101'),
  'Your order is on the way', 'the staff reply body is unchanged');

SELECT * FROM finish();
ROLLBACK;
