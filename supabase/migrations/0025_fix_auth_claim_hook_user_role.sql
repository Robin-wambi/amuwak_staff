-- 0025_fix_auth_claim_hook_user_role.sql
-- Fix custom_access_token_hook (migration 0009): it wrote the staff role into
-- the reserved `role` JWT claim. PostgREST reads `role` to choose the Postgres
-- role for each request (SET ROLE), so once the hook was enabled in the
-- dashboard, tokens carried role='manager'/'in_shop'/'driver' — none of which
-- are real Postgres roles — and PostgREST rejected every data request.
--
-- Move the staff role to a custom `user_role` claim and leave the reserved
-- `role` claim untouched. The Flutter app reads `user_role` (see
-- lib/src/auth/session.dart). RLS is unaffected: auth_staff_role() looks the
-- role up from the staff table by auth.uid(), not from any JWT claim.
--
-- CREATE OR REPLACE preserves the existing grants from 0009 (REVOKE from
-- public/anon/authenticated, GRANT EXECUTE to supabase_auth_admin).

CREATE OR REPLACE FUNCTION public.custom_access_token_hook(event jsonb)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  claims     jsonb;
  staff_role text;
BEGIN
  SELECT role INTO staff_role FROM public.staff
   WHERE id = (event->>'user_id')::uuid AND active = true;

  claims := event->'claims';
  claims := jsonb_set(claims, '{user_role}', to_jsonb(coalesce(staff_role, 'none')));
  RETURN jsonb_set(event, '{claims}', claims);
END;
$$;
