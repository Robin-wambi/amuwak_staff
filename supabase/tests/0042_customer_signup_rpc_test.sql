-- 0042_customer_signup_rpc_test.sql
BEGIN;
SET search_path TO extensions, public;

SELECT plan(7);

-- Normalisation parity vectors (must match Dart ugandaNationalDigits).
SELECT is(uganda_national_digits('0700123456'),      '700123456', 'local trunk form');
SELECT is(uganda_national_digits('+256 700 123 456'),'700123456', 'international form');
SELECT is(uganda_national_digits('256700123456'),    '700123456', 'bare international');
SELECT is(uganda_national_digits('700123456'),       '700123456', 'bare national');
SELECT is(uganda_national_digits('+256 0700 123456'),'700123456', 'redundant 256 + trunk zero');

-- Linking: an unowned customer with a matching phone gets claimed.
INSERT INTO public.customers (id, name, phone) VALUES
  ('00000000-0000-0000-0000-0000000000d1', 'Walk-in Joe', '0700123456');

SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claim.sub" = '00000000-0000-0000-0000-0000000000e1';
SELECT is(
  link_or_create_customer('Joe', '+256700123456', 'joe@example.com'),
  '00000000-0000-0000-0000-0000000000d1',
  'links to the existing customer by normalised phone');

-- Calling again is idempotent (same id, no second row).
SELECT is(
  link_or_create_customer('Joe', '0700123456', 'joe@example.com'),
  '00000000-0000-0000-0000-0000000000d1',
  'second call is idempotent');

SELECT * FROM finish();
ROLLBACK;
