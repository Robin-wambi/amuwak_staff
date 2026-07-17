-- 0041_customer_accounts_test.sql
BEGIN;
SET search_path TO extensions, public;

SELECT plan(4);

SELECT has_column('public', 'customers', 'auth_user_id', 'customers.auth_user_id exists');
SELECT has_column('public', 'customers', 'email',        'customers.email exists');

-- Two unlinked customers (NULL auth_user_id) coexist.
INSERT INTO public.customers (name, phone) VALUES ('A', '0700000001'), ('B', '0700000002');
SELECT pass('two NULL auth_user_id customers insert without unique violation');

-- The partial unique index rejects a duplicate non-null auth_user_id.
INSERT INTO public.customers (name, phone, auth_user_id)
  VALUES ('C', '0700000003', '00000000-0000-0000-0000-0000000000c1');
PREPARE dup_link AS
  INSERT INTO public.customers (name, phone, auth_user_id)
  VALUES ('D', '0700000004', '00000000-0000-0000-0000-0000000000c1');
SELECT throws_ok('dup_link', '23505', NULL, 'duplicate auth_user_id rejected');

SELECT * FROM finish();
ROLLBACK;
