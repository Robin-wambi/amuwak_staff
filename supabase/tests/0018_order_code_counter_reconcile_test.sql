-- 0018_order_code_counter_reconcile_test.sql
-- Verify next_order_code() reconciles against the highest order_code already in
-- orders for THE CURRENT YEAR, so a counter that has fallen behind can't
-- re-issue an existing code — while still honouring the counter when it is
-- ahead, and ignoring other years.
--
-- Runs inside BEGIN ... ROLLBACK, so the DELETEs + seeded orders + the codes it
-- issues never touch real production data. session_replication_role=replica
-- disables triggers + FK checks for the duration so the orders slate can be
-- cleared/seeded without tripping dependent-table FKs or the status state
-- machine (superuser-only; pgTAP runs as the postgres role).

BEGIN;
SET search_path TO extensions, public;

SELECT plan(7);

SELECT has_function('next_order_code');

-- Deterministic slate: clear counters AND orders for this transaction. Because
-- the function now reads orders, the orders table must be controlled too.
SET LOCAL session_replication_role = replica;
DELETE FROM public.order_code_counters;
DELETE FROM public.orders;

-- No orders, no counter → first code is 0001.
SELECT is(
  public.next_order_code(),
  'AMW-' || extract(year FROM now())::int::text || '-0001',
  'first code of the year is 0001 when nothing exists');

-- Counter has fallen behind: a current-year order already carries a higher
-- suffix (0050) than the counter knows about. Also seed a PRIOR-year order with
-- an even higher suffix (9999) that MUST be ignored — the reconciliation is
-- year-scoped. NOT-NULL FK columns get throwaway uuids (FK checks off here).
INSERT INTO public.orders (
  order_code, customer_name, phone, address, service_type, status,
  intake_method, fulfillment_method, item_count, intake_recorded_by, created_by)
VALUES
  ('AMW-' || extract(year FROM now())::int::text || '-0050',
   'Recon Test', '0700000000', 'addr', 'wash_only', 'pending_pickup',
   'driver_pickup', 'delivery', 1, gen_random_uuid(), gen_random_uuid()),
  ('AMW-' || (extract(year FROM now())::int - 1)::text || '-9999',
   'Last Year', '0700000001', 'addr', 'wash_only', 'pending_pickup',
   'driver_pickup', 'delivery', 1, gen_random_uuid(), gen_random_uuid()),
  -- Malformed current-year code with an oversized suffix: the 1-9 digit bound
  -- must ignore it rather than overflow the ::int cast (which would abort the
  -- function and block all order creation).
  ('AMW-' || extract(year FROM now())::int::text || '-99999999999',
   'Oversized', '0700000002', 'addr', 'wash_only', 'pending_pickup',
   'driver_pickup', 'delivery', 1, gen_random_uuid(), gen_random_uuid());

SET LOCAL session_replication_role = origin;

-- Counter at 1, current-year order 0050 exists; the prior-year 9999 and the
-- oversized-suffix code must NOT count: next code jumps past 0050 to 0051.
SELECT is(
  public.next_order_code(),
  'AMW-' || extract(year FROM now())::int::text || '-0051',
  'reconciles past current-year max; ignores other years + oversized suffixes');

SELECT is(
  (SELECT last_value FROM public.order_code_counters
     WHERE year = extract(year FROM now())::int)::int,
  51,
  'counter is bumped to the reconciled value');

-- Counter AHEAD of orders: force the counter past the max order suffix and
-- confirm GREATEST honours the counter side (normal monotonic increment), i.e.
-- reconciliation never drags the sequence backwards.
UPDATE public.order_code_counters
   SET last_value = 100
 WHERE year = extract(year FROM now())::int;

SELECT is(
  public.next_order_code(),
  'AMW-' || extract(year FROM now())::int::text || '-0101',
  'honours the counter when it is ahead of the orders table');

-- Permission model is unchanged by the replace: authenticated may EXECUTE...
SET LOCAL ROLE authenticated;

SELECT matches(
  public.next_order_code(),
  '^AMW-\d{4}-\d+$',
  'authenticated may still EXECUTE next_order_code()');

-- ...but still cannot read the counter table directly.
SELECT throws_ok(
  'SELECT 1 FROM public.order_code_counters',
  '42501', NULL,
  'authenticated is still denied direct access to the counter table');

SELECT * FROM finish();
ROLLBACK;
