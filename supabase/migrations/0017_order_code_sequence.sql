-- 0017_order_code_sequence.sql
-- Server-assigned, sequential, human-facing order codes (e.g. AMW-2026-0042).
--
-- Until now the client minted order_code as 'AMW-<millisecondsSinceEpoch>',
-- which is unreadable and could collide when two riders create an order in the
-- same millisecond. order_code is the value a rider reads back to a customer,
-- so it must be short, sequential, and unique.
--
-- next_order_code() atomically bumps a per-year counter and returns the
-- formatted code. The client calls it via RPC at order-creation time and stores
-- the result in orders.order_code (still text UNIQUE NOT NULL — see 0003).
-- Atomicity comes from the INSERT ... ON CONFLICT ... RETURNING, so concurrent
-- callers can never receive the same number. Numbers reset per calendar year.

CREATE TABLE order_code_counters (
  year       int PRIMARY KEY,
  last_value int NOT NULL
);

-- Only the SECURITY DEFINER function below should ever touch this table.
-- Enable RLS with no policies so direct access from `authenticated` is denied;
-- the definer function bypasses RLS to do its single atomic upsert. The REVOKE
-- is defense-in-depth: it makes the "no direct access" intent explicit so a
-- future SELECT policy can't silently expose the counter values.
ALTER TABLE order_code_counters ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE order_code_counters FROM PUBLIC, anon, authenticated;

CREATE FUNCTION next_order_code() RETURNS text
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  yr int := EXTRACT(year FROM now())::int;
  n  int;
BEGIN
  INSERT INTO order_code_counters (year, last_value)
  VALUES (yr, 1)
  ON CONFLICT (year)
    DO UPDATE SET last_value = order_code_counters.last_value + 1
  RETURNING last_value INTO n;

  -- lpad to a 4-digit minimum; longer once a year passes 9999 (no truncation).
  RETURN 'AMW-' || yr || '-' || lpad(n::text, 4, '0');
END;
$$;

REVOKE EXECUTE ON FUNCTION next_order_code() FROM public;
GRANT  EXECUTE ON FUNCTION next_order_code() TO authenticated;
