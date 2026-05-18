-- 0010_tighten_orders_rls.sql
-- Address two gaps surfaced by code review:
--
-- 1. orders_update had no WITH CHECK clause, letting a driver UPDATE their
--    assigned order and reassign it to a different driver (or escalate fields
--    like `created_by`). USING controls which rows can be targeted; WITH CHECK
--    controls what they look like after the write.
--
-- 2. orders_insert did not constrain `status`, letting a driver INSERT an
--    order at status='completed' directly — bypassing the status-transition
--    validator (which only fires on order_status_events). Initial status is
--    now pinned per intake_method.

DROP POLICY orders_update ON orders;
DROP POLICY orders_insert ON orders;

CREATE POLICY orders_update ON orders FOR UPDATE
  USING (
    auth_staff_role() IN ('in_shop','manager')
    OR (auth_staff_role() = 'driver' AND assigned_driver = auth.uid())
  )
  WITH CHECK (
    auth_staff_role() IN ('in_shop','manager')
    OR (auth_staff_role() = 'driver' AND assigned_driver = auth.uid())
  );

CREATE POLICY orders_insert ON orders FOR INSERT WITH CHECK (
  CASE auth_staff_role()
    WHEN 'driver'  THEN
      intake_method = 'driver_pickup'
      AND status              = 'pending_pickup'
      AND assigned_driver     = auth.uid()
      AND intake_recorded_by  = auth.uid()
      AND created_by          = auth.uid()
    WHEN 'in_shop' THEN
      created_by = auth.uid()
      AND status IN (
        CASE intake_method
          WHEN 'walk_in'        THEN 'received'
          WHEN 'driver_pickup'  THEN 'pending_pickup'
          WHEN 'phone_order'    THEN 'pending_pickup'
        END
      )
    WHEN 'manager' THEN
      created_by = auth.uid()
      AND status IN (
        CASE intake_method
          WHEN 'walk_in'        THEN 'received'
          WHEN 'driver_pickup'  THEN 'pending_pickup'
          WHEN 'phone_order'    THEN 'pending_pickup'
        END
      )
    ELSE false
  END
);
