-- 0012_validate_transition_with_lock.sql
-- Harden validate_status_transition() against two issues:
--
-- 1. Race: concurrent transitions on the same order both read the same
--    intake/fulfillment without locking. SELECT … FOR UPDATE serializes
--    them on the orders row.
--
-- 2. Stale from_status: the previous version only checked the (from -> to)
--    edge against the matrix; it did not verify that orders.status actually
--    equals NEW.from_status. A client could send a stale event after another
--    transition has already landed. Now we require the claimed `from_status`
--    to match the order's current status.

CREATE OR REPLACE FUNCTION validate_status_transition() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  o_intake       text;
  o_fulfillment  text;
  current_status text;
  edge_ok        boolean;
BEGIN
  SELECT intake_method, fulfillment_method, status
    INTO o_intake, o_fulfillment, current_status
  FROM orders
  WHERE id = NEW.order_id
  FOR UPDATE;

  IF o_intake IS NULL THEN
    RAISE EXCEPTION 'order % not found when validating status transition', NEW.order_id;
  END IF;

  IF current_status IS DISTINCT FROM NEW.from_status THEN
    RAISE EXCEPTION 'stale transition: order % is currently in % but event claims from %',
      NEW.order_id, current_status, NEW.from_status;
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM valid_transitions
    WHERE intake_method      = o_intake
      AND fulfillment_method = o_fulfillment
      AND from_status IS NOT DISTINCT FROM NEW.from_status
      AND to_status          = NEW.to_status
  ) INTO edge_ok;

  IF NOT edge_ok THEN
    RAISE EXCEPTION 'illegal status transition: % -> % for (%, %)',
      NEW.from_status, NEW.to_status, o_intake, o_fulfillment;
  END IF;

  UPDATE orders SET status = NEW.to_status WHERE id = NEW.order_id;

  RETURN NEW;
END;
$$;
