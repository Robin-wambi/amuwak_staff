-- 0005a_fix_updated_at_clock.sql
-- The original set_updated_at() used now(), which returns the transaction
-- start time — so when an INSERT and UPDATE happen in the same transaction
-- (the common pgTAP test pattern), `updated_at` doesn't advance past
-- `created_at`. clock_timestamp() returns wall-clock time and is the right
-- choice for an "actually changed at" stamp.

CREATE OR REPLACE FUNCTION set_updated_at() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = clock_timestamp();
  RETURN NEW;
END;
$$;
