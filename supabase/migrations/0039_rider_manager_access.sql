-- 0039_rider_manager_access.sql
-- TEMPORARY ("for now") elevation: give the rider (role='driver') the same
-- database access a manager has.
--
-- Why: in online-only mode the app writes to Supabase directly as the logged-in
-- rider, and the driver role is too narrow for the rider workflow — most
-- visibly, `customers_write` (0007) excludes 'driver', so creating a New Pickup
-- (which upserts a customer first) fails with "write did not persist", and
-- `orders_insert` (0010) requires a driver to self-set assigned_driver, which the
-- client never does.
--
-- Rather than re-plumb every policy, we collapse 'driver' into 'manager' in the
-- single helper every RLS policy already branches on (auth_staff_role(), 0007).
-- One change uniformly grants drivers full manager parity: write customers,
-- create orders via the manager branch (no assigned_driver required), see/edit/
-- delete all orders, manage staff, and edit pricing. The `WHEN 'driver'` arms of
-- the order policies simply become unreachable.
--
-- This does NOT touch the JWT `user_role` claim (custom_access_token_hook,
-- 0009/0025): tokens still carry 'driver', so the app UI keeps the rider
-- screens — only database permissions are elevated.
--
-- Reversible: restore the original body (SELECT role …) to drop drivers back to
-- their own role. When a narrower, permanent model is designed, replace this.

CREATE OR REPLACE FUNCTION auth_staff_role() RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public AS $$
  SELECT CASE WHEN role = 'driver' THEN 'manager' ELSE role END
  FROM staff WHERE id = auth.uid() AND active = true
$$;

-- CREATE OR REPLACE preserves existing privileges, but re-assert them so the
-- grant is explicit and a fresh apply matches 0007's house style exactly.
REVOKE EXECUTE ON FUNCTION auth_staff_role() FROM public;
GRANT  EXECUTE ON FUNCTION auth_staff_role() TO authenticated;
