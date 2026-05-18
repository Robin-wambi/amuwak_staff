-- 0014_fix_assigned_driver_trigger_security.sql
-- check_assigned_driver_role() runs inside an INSERT/UPDATE on orders and
-- queries the staff table. Without SECURITY DEFINER it runs as the caller
-- (e.g. a driver), which means staff RLS hides every staff row that isn't
-- the caller — so the EXISTS always returns false for any driver looking up
-- a different driver, and the trigger raises "must reference an active staff
-- row" even for legitimate cases.
--
-- This both masked the RLS WITH CHECK that should be the primary defence
-- against drivers reassigning orders, and would prevent managers/in-shop
-- staff from assigning orders to specific drivers via PostgREST.
--
-- SECURITY DEFINER makes the trigger run with the function owner's
-- privileges (postgres role), bypassing RLS on staff. RLS on orders itself
-- still gates who is allowed to set assigned_driver — this trigger only
-- validates the *target*.

CREATE OR REPLACE FUNCTION check_assigned_driver_role() RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public AS $$
BEGIN
  IF NEW.assigned_driver IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM staff
      WHERE id = NEW.assigned_driver AND role = 'driver' AND active = true
    ) THEN
      RAISE EXCEPTION 'assigned_driver % must reference an active staff row with role=driver',
        NEW.assigned_driver;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
