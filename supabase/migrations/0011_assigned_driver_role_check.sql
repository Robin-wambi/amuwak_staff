-- 0011_assigned_driver_role_check.sql
-- Enforce that orders.assigned_driver, if set, references a staff row with
-- role='driver'. Without this guard a manager (or a buggy client) could
-- assign an order to a non-driver, hiding it from every real driver via the
-- orders RLS read policy.

CREATE FUNCTION check_assigned_driver_role() RETURNS trigger
LANGUAGE plpgsql AS $$
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

CREATE TRIGGER orders_check_assigned_driver
  BEFORE INSERT OR UPDATE OF assigned_driver ON orders
  FOR EACH ROW EXECUTE FUNCTION check_assigned_driver_role();
