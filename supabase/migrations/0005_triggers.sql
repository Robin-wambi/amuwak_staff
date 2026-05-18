-- 0005_triggers.sql
-- Two trigger families:
--
-- 1. `set_updated_at()` — generic BEFORE UPDATE trigger, attached to every
--    table that carries an `updated_at` column.
--
-- 2. `validate_status_transition()` — BEFORE INSERT on `order_status_events`,
--    rejecting any (from_status -> to_status) that is not in the order's
--    legal transition matrix and mirroring the new status into `orders.status`
--    as a denormalized cache.

-- Generic updated_at trigger function
CREATE FUNCTION set_updated_at() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER staff_set_updated_at        BEFORE UPDATE ON staff
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER customers_set_updated_at    BEFORE UPDATE ON customers
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER orders_set_updated_at       BEFORE UPDATE ON orders
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER proof_events_set_updated_at BEFORE UPDATE ON proof_events
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Status transition validator
CREATE FUNCTION validate_status_transition() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  o_intake      text;
  o_fulfillment text;
  ok            boolean;
BEGIN
  SELECT intake_method, fulfillment_method INTO o_intake, o_fulfillment
  FROM orders WHERE id = NEW.order_id;

  IF o_intake IS NULL THEN
    RAISE EXCEPTION 'order % not found when validating status transition', NEW.order_id;
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM valid_transitions
    WHERE intake_method = o_intake
      AND fulfillment_method = o_fulfillment
      AND from_status IS NOT DISTINCT FROM NEW.from_status
      AND to_status = NEW.to_status
  ) INTO ok;

  IF NOT ok THEN
    RAISE EXCEPTION 'illegal status transition: % -> % for (%, %)',
      NEW.from_status, NEW.to_status, o_intake, o_fulfillment;
  END IF;

  -- Mirror into orders.status as a denormalized cache so list views don't
  -- need to subquery the event log.
  UPDATE orders SET status = NEW.to_status WHERE id = NEW.order_id;

  RETURN NEW;
END;
$$;

CREATE TRIGGER order_status_events_validate
  BEFORE INSERT ON order_status_events
  FOR EACH ROW EXECUTE FUNCTION validate_status_transition();
