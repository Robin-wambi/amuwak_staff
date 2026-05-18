-- 0009_auth_claim_hook_test.sql
-- Verify custom_access_token_hook exists and injects the staff role into
-- the JWT claims payload.

BEGIN;
SET search_path TO extensions, public;

SELECT plan(3);

INSERT INTO public.staff (id, username, display_name, role) VALUES
  ('00000000-0000-0000-0000-000000000050', 'mgr_hook_test', 'Mgr 2', 'manager');

SELECT has_function('public', 'custom_access_token_hook', ARRAY['jsonb']);

-- For a known manager, the role claim is injected as 'manager'
SELECT is(
  (public.custom_access_token_hook(jsonb_build_object(
     'user_id', '00000000-0000-0000-0000-000000000050',
     'claims',  jsonb_build_object('sub', '00000000-0000-0000-0000-000000000050')
   ))->'claims'->>'role')::text,
  'manager',
  'role claim is injected for a manager');

-- For an unknown user, the role claim falls back to 'none'
SELECT is(
  (public.custom_access_token_hook(jsonb_build_object(
     'user_id', '00000000-0000-0000-0000-000000099999',
     'claims',  jsonb_build_object('sub', '00000000-0000-0000-0000-000000099999')
   ))->'claims'->>'role')::text,
  'none',
  'role claim falls back to "none" for an unknown user');

SELECT * FROM finish();
ROLLBACK;
