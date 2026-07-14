-- 0043_customer_role_hook_test.sql
BEGIN;
SET search_path TO extensions, public;

SELECT plan(4);

INSERT INTO public.staff (id, username, display_name, role) VALUES
  ('00000000-0000-0000-0000-0000000000f1', 'mgr_hook2', 'Mgr', 'manager');
INSERT INTO public.customers (id, name, phone, auth_user_id) VALUES
  ('00000000-0000-0000-0000-0000000000f2', 'Cust', '0700111222',
   '00000000-0000-0000-0000-0000000000f3');

-- staff branch unchanged
SELECT is(
  (custom_access_token_hook(jsonb_build_object(
     'user_id','00000000-0000-0000-0000-0000000000f1',
     'claims', jsonb_build_object('sub','x')))->'claims'->>'user_role'),
  'manager', 'staff still resolves to their role');

-- linked customer → 'customer'
SELECT is(
  (custom_access_token_hook(jsonb_build_object(
     'user_id','00000000-0000-0000-0000-0000000000f3',
     'claims', jsonb_build_object('sub','x')))->'claims'->>'user_role'),
  'customer', 'linked customer resolves to customer');

-- neither → 'none'
SELECT is(
  (custom_access_token_hook(jsonb_build_object(
     'user_id','00000000-0000-0000-0000-000000099999',
     'claims', jsonb_build_object('sub','x')))->'claims'->>'user_role'),
  'none', 'unknown user resolves to none');

-- reserved role claim preserved
SELECT is(
  (custom_access_token_hook(jsonb_build_object(
     'user_id','00000000-0000-0000-0000-0000000000f3',
     'claims', jsonb_build_object('role','authenticated')))->'claims'->>'role'),
  'authenticated', 'reserved role claim untouched');

SELECT * FROM finish();
ROLLBACK;
