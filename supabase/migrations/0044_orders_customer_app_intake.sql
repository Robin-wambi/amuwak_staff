-- 0044_orders_customer_app_intake.sql
-- Let customers place their own orders from the app.
--
-- 1. Add 'customer_app' to the intake_method CHECK (the inline CHECK from 0003
--    is auto-named orders_intake_method_check).
-- 2. customer_app orders start at pending_pickup and then follow driver_pickup's
--    path, for both fulfillment methods — copy driver_pickup's rows (same trick
--    0003 used for phone_order).
-- 3. placed_by_customer_id records WHO placed it (the customer), so staff UI can
--    show "Placed by <customer> via app". created_by/intake_recorded_by must
--    stay NOT NULL REFERENCES staff(id), so customer orders point those at a
--    system sentinel staff row; the real originator is placed_by_customer_id
--    (and customer_id).
-- 4. Insert the sentinel staff row (fixed id; inactive). staff.id has no FK to
--    auth.users, so this is a plain insert.

ALTER TABLE orders DROP CONSTRAINT orders_intake_method_check;
ALTER TABLE orders ADD  CONSTRAINT orders_intake_method_check
  CHECK (intake_method IN ('driver_pickup','walk_in','phone_order','customer_app'));

INSERT INTO valid_transitions (intake_method, fulfillment_method, from_status, to_status)
SELECT 'customer_app', fulfillment_method, from_status, to_status
FROM valid_transitions
WHERE intake_method = 'driver_pickup'
ON CONFLICT ON CONSTRAINT valid_transitions_natural_key DO NOTHING;

ALTER TABLE orders
  ADD COLUMN placed_by_customer_id uuid REFERENCES customers(id);

INSERT INTO staff (id, username, display_name, role, active) VALUES
  ('00000000-0000-0000-0000-00000000a001', 'system_customer_app',
   'Customer App', 'in_shop', false)
ON CONFLICT (id) DO NOTHING;
