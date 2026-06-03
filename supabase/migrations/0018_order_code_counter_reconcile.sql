-- 0018_order_code_counter_reconcile.sql
-- Make next_order_code() self-healing against a counter that has fallen behind
-- the orders table.
--
-- 0017's next_order_code() trusts order_code_counters.last_value alone. If that
-- table is ever restored from an older backup, reset, or otherwise diverges
-- from orders, the blind increment can re-issue a code that already exists in
-- orders.order_code (UNIQUE NOT NULL, see 0003). The order INSERT would then
-- fail on the unique constraint and silently block order creation.
--
-- This replaces the function so the next value is reconciled against the
-- highest suffix already persisted in orders for the year:
--   next = GREATEST(counter.last_value, max(existing orders suffix)) + 1
-- A stale counter therefore jumps PAST the existing codes instead of colliding.
-- Normal operation (counter at or ahead of orders) is unchanged. Atomicity is
-- still provided by the single INSERT ... ON CONFLICT ... RETURNING (the row is
-- locked on conflict, so concurrent callers serialise on it). Gaps remain
-- expected and acceptable, exactly as documented in 0017.

CREATE OR REPLACE FUNCTION public.next_order_code() RETURNS text
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  yr       int := EXTRACT(year FROM now())::int;
  max_used int;
  n        int;
BEGIN
  -- Highest counter suffix already minted for this year, parsed back out of the
  -- AMW-<yr>-<digits> codes. 0 when there are none. The suffix is bounded to
  -- 1-9 digits so a malformed/imported code with an oversized suffix can't
  -- overflow the ::int cast (which would abort the function and block all order
  -- creation); such codes simply aren't considered.
  SELECT COALESCE(MAX(substring(order_code FROM '^AMW-' || yr || '-(\d{1,9})$')::int), 0)
    INTO max_used
    FROM orders
   WHERE order_code ~ ('^AMW-' || yr || '-\d{1,9}$');

  INSERT INTO order_code_counters (year, last_value)
  VALUES (yr, GREATEST(1, max_used + 1))
  ON CONFLICT (year)
    DO UPDATE SET last_value =
      GREATEST(order_code_counters.last_value, max_used) + 1
  RETURNING last_value INTO n;

  -- lpad to a 4-digit minimum; longer once a year passes 9999 (no truncation).
  RETURN 'AMW-' || yr || '-' || lpad(n::text, 4, '0');
END;
$$;

-- CREATE OR REPLACE preserves the existing grants from 0017, but re-assert them
-- so the permission model stays explicit and self-contained in this migration.
REVOKE EXECUTE ON FUNCTION public.next_order_code() FROM public;
GRANT  EXECUTE ON FUNCTION public.next_order_code() TO authenticated;
