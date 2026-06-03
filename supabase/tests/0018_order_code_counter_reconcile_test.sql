-- 0018_order_code_counter_reconcile_test.sql
-- Verify next_order_code() reconciles against the highest order_code already in
-- orders, so a counter that has fallen behind can't re-issue an existing code.
--
-- Runs inside BEGIN ... ROLLBACK, so the DELETEs + the seeded order + the codes
-- it issues never touch real production data. session_replication_role=replica
-- disables triggers + FK checks for the duration so the orders slate can be
-- cleared/seeded without tripping dependent-table FKs or the status state
-- machine (superuser-only; pgTAP runs as the postgres role).

BEGIN;
SET search_path TO extensions, public;

SELECT plan(6);

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

-- Simulate a counter that has fallen behind: an order already carries a higher
-- suffix (0050) than the counter knows about. NOT-NULL FK columns are filled
-- with throwaway uuids (FK checks are off under replica role).
INSERT INTO public.orders (
  order_code, customer_name, phone, address, service_type, status,
  intake_method, fulfillment_method, item_count, intake_recorded_by, created_by)
VALUES (
  'AMW-' || extract(year FROM now())::int::text || '-0050',
  'Recon Test', '0700000000', 'addr', 'wash_only', 'pending_pickup',
  'driver_pickup', 'delivery', 1, gen_random_uuid(), gen_random_uuid());

SET LOCAL session_replication_role = origin;

-- The counter is at 1, but order 0050 exists: the next code must jump PAST it.
SELECT is(
  public.next_order_code(),
  'AMW-' || extract(year FROM now())::int::text || '-0051',
  'reconciles past the max existing order_code suffix (no collision)');

SELECT is(
  (SELECT last_value FROM public.order_code_counters
     WHERE year = extract(year FROM now())::int)::int,
  51,
  'counter is bumped to the reconciled value');

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
