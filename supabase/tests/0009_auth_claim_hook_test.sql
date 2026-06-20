-- 0009_auth_claim_hook_test.sql
-- Verify custom_access_token_hook exists and injects the staff role into the
-- JWT claims payload under the `user_role` claim — NOT the reserved `role`
-- claim, which PostgREST uses to choose the request's Postgres role (see
-- migration 0025).

BEGIN;
SET search_path TO extensions, public;

SELECT plan(6);

INSERT INTO public.staff (id, username, display_name, role) VALUES
  ('00000000-0000-0000-0000-000000000050', 'mgr_hook_test', 'Mgr 2', 'manager'),
  ('00000000-0000-0000-0000-000000000051', 'shop_hook_test', 'Shop 1', 'in_shop'),
  ('00000000-0000-0000-0000-000000000052', 'drv_hook_test', 'Driver 1', 'driver');

SELECT has_function('public', 'custom_access_token_hook', ARRAY['jsonb']);

-- For a known manager, the role is injected into the `user_role` claim
SELECT is(
  (public.custom_access_token_hook(jsonb_build_object(
     'user_id', '00000000-0000-0000-0000-000000000050',
     'claims',  jsonb_build_object('sub', '00000000-0000-0000-0000-000000000050')
   ))->'claims'->>'user_role')::text,
  'manager',
  'user_role claim is injected for a manager');

-- The hook is role-agnostic: an in_shop staff member gets 'in_shop'
SELECT is(
  (public.custom_access_token_hook(jsonb_build_object(
     'user_id', '00000000-0000-0000-0000-000000000051',
     'claims',  jsonb_build_object('sub', '00000000-0000-0000-0000-000000000051')
   ))->'claims'->>'user_role')::text,
  'in_shop',
  'user_role claim is injected for an in_shop staff member');

-- ...and a driver gets 'driver'
SELECT is(
  (public.custom_access_token_hook(jsonb_build_object(
     'user_id', '00000000-0000-0000-0000-000000000052',
     'claims',  jsonb_build_object('sub', '00000000-0000-0000-0000-000000000052')
   ))->'claims'->>'user_role')::text,
  'driver',
  'user_role claim is injected for a driver');

-- For an unknown user, the role falls back to 'none'
SELECT is(
  (public.custom_access_token_hook(jsonb_build_object(
     'user_id', '00000000-0000-0000-0000-000000099999',
     'claims',  jsonb_build_object('sub', '00000000-0000-0000-0000-000000099999')
   ))->'claims'->>'user_role')::text,
  'none',
  'user_role claim falls back to "none" for an unknown user');

-- The reserved `role` claim (used by PostgREST for SET ROLE) is left untouched.
SELECT is(
  (public.custom_access_token_hook(jsonb_build_object(
     'user_id', '00000000-0000-0000-0000-000000000050',
     'claims',  jsonb_build_object('role', 'authenticated')
   ))->'claims'->>'role')::text,
  'authenticated',
  'reserved role claim is preserved, not overwritten');

SELECT * FROM finish();
ROLLBACK;
