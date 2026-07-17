-- 0046_customer_rls.sql
-- Additive RLS so a customer can read ONLY their own orders/messages and place
-- their own orders/messages. Every policy here is a NEW permissive policy;
-- nothing existing is dropped or altered (permissive policies OR together, so
-- staff visibility is unchanged). Status-event reads, proof_events and
-- proof_photos already gate on order visibility via EXISTS(orders), so a
-- customer who can SELECT their order automatically sees its events/proofs —
-- no new policy needed there (asserted in the sibling test).

-- Customer analogue of auth_staff_role(): the caller's linked customers.id.
CREATE FUNCTION auth_customer_id() RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public AS $$
  SELECT id FROM customers WHERE auth_user_id = auth.uid() AND deleted_at IS NULL
$$;

REVOKE EXECUTE ON FUNCTION auth_customer_id() FROM public;
GRANT  EXECUTE ON FUNCTION auth_customer_id() TO authenticated;

-- orders: a customer reads their own; inserts a customer_app order pinned to
-- pending_pickup, self-attributed, with staff id columns set to the sentinel.
CREATE POLICY orders_customer_read ON orders FOR SELECT
  USING (customer_id = auth_customer_id());

CREATE POLICY orders_customer_insert ON orders FOR INSERT WITH CHECK (
  auth_customer_id() IS NOT NULL
  AND customer_id           = auth_customer_id()
  AND placed_by_customer_id = auth_customer_id()
  AND intake_method         = 'customer_app'
  AND status                = 'pending_pickup'
  AND fulfillment_method IN ('delivery','customer_collect')
  AND created_by            = '00000000-0000-0000-0000-00000000a001'
  AND intake_recorded_by    = '00000000-0000-0000-0000-00000000a001'
);
-- (No customer UPDATE policy → customers cannot advance status or edit price.)

-- order_messages: staff (any active) or the owning customer may read; each side
-- inserts self-attributed messages on a visible order; either may mark read.
--
-- DELIBERATE: staff access here is a bare role check, NOT scoped through
-- EXISTS(orders) the way status_events_read / proof_events_read are. Those
-- inherit driver scoping for free (orders_read limits a driver to their assigned
-- or unassigned orders, and the subquery is itself RLS-filtered). Order chat is
-- instead a shared support inbox: any active staff member can read and reply on
-- any order, including one assigned to another driver. That is the intended
-- product behaviour — do not "fix" this to match the other tables without
-- changing the support model first.
CREATE POLICY order_messages_read ON order_messages FOR SELECT USING (
  auth_staff_role() IN ('driver','in_shop','manager')
  OR EXISTS (SELECT 1 FROM orders o
             WHERE o.id = order_id AND o.customer_id = auth_customer_id())
);

CREATE POLICY order_messages_customer_insert ON order_messages FOR INSERT WITH CHECK (
  sender_kind = 'customer'
  AND sender_id = auth_customer_id()
  AND EXISTS (SELECT 1 FROM orders o
              WHERE o.id = order_id AND o.customer_id = auth_customer_id())
);

CREATE POLICY order_messages_staff_insert ON order_messages FOR INSERT WITH CHECK (
  auth_staff_role() IN ('driver','in_shop','manager')
  AND sender_kind = 'staff'
  AND sender_id = auth.uid()
);

CREATE POLICY order_messages_mark_read ON order_messages FOR UPDATE
  USING (
    auth_staff_role() IN ('driver','in_shop','manager')
    OR EXISTS (SELECT 1 FROM orders o
               WHERE o.id = order_id AND o.customer_id = auth_customer_id())
  )
  WITH CHECK (
    auth_staff_role() IN ('driver','in_shop','manager')
    OR EXISTS (SELECT 1 FROM orders o
               WHERE o.id = order_id AND o.customer_id = auth_customer_id())
  );

-- RLS is row-level only: order_messages_mark_read gates WHICH ROWS a caller may
-- update, never WHICH COLUMNS. On its own it would let anyone who can see a
-- message rewrite body / sender_kind / sender_id — a customer could edit a staff
-- reply's text, or forge attribution — because Supabase's default schema grants
-- hand table-wide UPDATE to authenticated. Take that back and re-grant only the
-- column the policy is named for, so the two gates together mean "the right
-- people may mark the right messages read, and nothing else".
REVOKE UPDATE ON order_messages FROM anon, authenticated;
GRANT  UPDATE (read_at) ON order_messages TO authenticated;

-- customers: a customer reads their own profile row (name, phone, custom rate).
CREATE POLICY customers_self_read ON customers FOR SELECT
  USING (auth_user_id = auth.uid());

-- pricing reference: customers need rate/fee/catalog to compute an estimate.
CREATE POLICY pricing_settings_customer_read ON pricing_settings FOR SELECT
  USING (auth_customer_id() IS NOT NULL);
CREATE POLICY pricing_catalog_items_customer_read ON pricing_catalog_items FOR SELECT
  USING (auth_customer_id() IS NOT NULL);
