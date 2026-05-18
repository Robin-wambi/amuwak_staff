-- 0007_rls.sql
-- Row-Level Security on every app table.
--
-- Helper auth_staff_role() returns the active role for the current auth.uid()
-- so policies can branch on driver / in_shop / manager. It is SECURITY DEFINER
-- so it bypasses RLS on the staff table itself (which is necessary — RLS on
-- staff is enforced via its own policies below).
--
-- Drivers see only their own assigned orders. In-shop staff see everything.
-- Managers see everything. Order creation is gated by intake_method (drivers
-- can only create driver_pickup orders for themselves).

CREATE FUNCTION auth_staff_role() RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public AS $$
  SELECT role FROM staff WHERE id = auth.uid() AND active = true
$$;

REVOKE EXECUTE ON FUNCTION auth_staff_role() FROM public;
GRANT  EXECUTE ON FUNCTION auth_staff_role() TO authenticated;

-- Enable RLS on every app table
ALTER TABLE staff               ENABLE ROW LEVEL SECURITY;
ALTER TABLE customers           ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders              ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_status_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE proof_events        ENABLE ROW LEVEL SECURITY;
ALTER TABLE proof_photos        ENABLE ROW LEVEL SECURITY;
ALTER TABLE issues              ENABLE ROW LEVEL SECURITY;
ALTER TABLE shifts              ENABLE ROW LEVEL SECURITY;
ALTER TABLE valid_transitions   ENABLE ROW LEVEL SECURITY;

-- valid_transitions: read-only reference data, readable by any signed-in user
CREATE POLICY valid_transitions_read ON valid_transitions FOR SELECT
  USING (auth.role() = 'authenticated');

-- staff: read self + managers see all; write only managers
CREATE POLICY staff_self_read ON staff FOR SELECT
  USING (id = auth.uid() OR auth_staff_role() = 'manager');
CREATE POLICY staff_manager_write ON staff FOR ALL
  USING      (auth_staff_role() = 'manager')
  WITH CHECK (auth_staff_role() = 'manager');

-- customers: any authenticated staff can read; in_shop/manager can write
CREATE POLICY customers_read ON customers FOR SELECT
  USING (auth_staff_role() IN ('driver','in_shop','manager'));
CREATE POLICY customers_write ON customers FOR ALL
  USING      (auth_staff_role() IN ('in_shop','manager'))
  WITH CHECK (auth_staff_role() IN ('in_shop','manager'));

-- orders: driver sees only their assigned (or unassigned) orders
CREATE POLICY orders_read ON orders FOR SELECT USING (
  CASE auth_staff_role()
    WHEN 'driver'  THEN assigned_driver = auth.uid() OR assigned_driver IS NULL
    WHEN 'in_shop' THEN true
    WHEN 'manager' THEN true
    ELSE false
  END
);

CREATE POLICY orders_insert ON orders FOR INSERT WITH CHECK (
  CASE auth_staff_role()
    WHEN 'driver'  THEN
      intake_method = 'driver_pickup'
      AND assigned_driver    = auth.uid()
      AND intake_recorded_by = auth.uid()
      AND created_by         = auth.uid()
    WHEN 'in_shop' THEN created_by = auth.uid()
    WHEN 'manager' THEN created_by = auth.uid()
    ELSE false
  END
);

CREATE POLICY orders_update ON orders FOR UPDATE USING (
  auth_staff_role() IN ('in_shop','manager')
  OR (auth_staff_role() = 'driver' AND assigned_driver = auth.uid())
);

-- order_status_events: append-only; readable iff the underlying order is readable.
-- We omit UPDATE and DELETE policies, which means those operations are denied
-- by RLS for non-service-role users.
CREATE POLICY status_events_insert ON order_status_events FOR INSERT
  WITH CHECK (changed_by = auth.uid());
CREATE POLICY status_events_read ON order_status_events FOR SELECT USING (
  EXISTS (SELECT 1 FROM orders o WHERE o.id = order_id)
);

-- proof_events: read piggybacks on orders RLS; insert requires self-attribution
CREATE POLICY proof_events_read ON proof_events FOR SELECT USING (
  EXISTS (SELECT 1 FROM orders o WHERE o.id = order_id)
);
CREATE POLICY proof_events_insert ON proof_events FOR INSERT
  WITH CHECK (captured_by = auth.uid());

-- proof_photos: piggyback on proof_events visibility + self-attribution on write
CREATE POLICY proof_photos_read ON proof_photos FOR SELECT USING (
  EXISTS (SELECT 1 FROM proof_events pe WHERE pe.id = proof_event_id)
);
CREATE POLICY proof_photos_insert ON proof_photos FOR INSERT
  WITH CHECK (
    EXISTS (SELECT 1 FROM proof_events pe
            WHERE pe.id = proof_event_id AND pe.captured_by = auth.uid())
  );

-- issues: any signed-in staff can read; insert requires self-attribution
CREATE POLICY issues_read ON issues FOR SELECT
  USING (auth_staff_role() IN ('driver','in_shop','manager'));
CREATE POLICY issues_insert ON issues FOR INSERT
  WITH CHECK (reported_by = auth.uid());

-- shifts: self-only; managers can see all
CREATE POLICY shifts_self ON shifts FOR ALL
  USING      (staff_id = auth.uid() OR auth_staff_role() = 'manager')
  WITH CHECK (staff_id = auth.uid() OR auth_staff_role() = 'manager');
