-- 0042_customer_signup_rpc_test.sql
BEGIN;
SET search_path TO extensions, public;

SELECT plan(10);

-- Normalisation parity vectors (must match Dart ugandaNationalDigits).
SELECT is(uganda_national_digits('0700123456'),      '700123456', 'local trunk form');
SELECT is(uganda_national_digits('+256 700 123 456'),'700123456', 'international form');
SELECT is(uganda_national_digits('256700123456'),    '700123456', 'bare international');
SELECT is(uganda_national_digits('700123456'),       '700123456', 'bare national');
SELECT is(uganda_national_digits('+256 0700 123456'),'700123456', 'redundant 256 + trunk zero');

-- A walk-in customer the shop recorded before the app existed: no linked auth
-- user, and a phone number that is public knowledge to anyone who has called it.
INSERT INTO public.customers (id, name, phone) VALUES
  ('00000000-0000-0000-0000-0000000000d1', 'Walk-in Joe', '0700123456');

SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claim.sub" = '00000000-0000-0000-0000-0000000000e1';

-- Signup is email+password (0041), so p_phone is unverified caller input.
-- Supplying the walk-in's number must NOT hand over their record.
SELECT isnt(
  link_or_create_customer('Joe', '+256700123456', 'joe@example.com'),
  '00000000-0000-0000-0000-0000000000d1',
  'a matching phone does NOT claim the existing walk-in customer');

-- Repeat calls return the same row rather than creating a second one.
SELECT is(
  link_or_create_customer('Joe', '0700123456',       'joe@example.com'),
  link_or_create_customer('Joe', '+256 700 123 456', 'joe@example.com'),
  'repeat calls are idempotent (same customer id)');

-- Inspect the results privileged: under RLS the caller only sees their own row.
RESET ROLE;

SELECT is(
  (SELECT auth_user_id FROM customers
    WHERE id = '00000000-0000-0000-0000-0000000000d1'),
  NULL::uuid,
  'the walk-in customer row is left unowned');

SELECT is(
  (SELECT count(*)::int FROM customers
    WHERE auth_user_id = '00000000-0000-0000-0000-0000000000e1'),
  1, 'signup creates exactly one customer row for the auth user');

SELECT is(
  (SELECT name FROM customers
    WHERE id = '00000000-0000-0000-0000-0000000000d1'),
  'Walk-in Joe', 'the walk-in customer row is otherwise untouched');

SELECT * FROM finish();
ROLLBACK;
