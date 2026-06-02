-- 0017_order_code_sequence_test.sql
-- Verify next_order_code() issues sequential, per-year, AMW-formatted codes
-- and that the backing counter table is reachable only via the function
-- (authenticated may EXECUTE the function but not read the table directly).
--
-- The whole file runs inside BEGIN ... ROLLBACK, so the DELETE + the codes it
-- issues never touch the real production counter.

BEGIN;
SET search_path TO extensions, public;

SELECT plan(8);

SELECT has_function('public', 'next_order_code');
SELECT has_table('public', 'order_code_counters');

-- Deterministic slate for this transaction (rolled back at the end).
DELETE FROM public.order_code_counters;

SELECT is(
  public.next_order_code(),
  'AMW-' || extract(year FROM now())::int::text || '-0001',
  'first code of the year is zero-padded 0001');

SELECT is(
  public.next_order_code(),
  'AMW-' || extract(year FROM now())::int::text || '-0002',
  'second call increments the counter to 0002');

SELECT matches(
  public.next_order_code(),
  '^AMW-\d{4}-\d{4,}$',
  'code matches the AMW-YYYY-NNNN shape');

SELECT is(
  (SELECT last_value FROM public.order_code_counters
     WHERE year = extract(year FROM now())::int)::int,
  3,
  'counter row tracks the number of codes issued this year');

-- The end-to-end permission model: an authenticated client can mint a code...
SET LOCAL ROLE authenticated;

SELECT matches(
  public.next_order_code(),
  '^AMW-\d{4}-\d+$',
  'authenticated may EXECUTE next_order_code()');

-- ...but cannot read or tamper with the counter table directly (REVOKE ALL).
SELECT throws_ok(
  'SELECT 1 FROM public.order_code_counters',
  '42501', NULL,
  'authenticated is denied direct access to the counter table');

SELECT * FROM finish();
ROLLBACK;
