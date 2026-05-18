-- 0009_auth_claim_hook.sql
-- Custom access token hook that injects the caller's staff role as the
-- `role` claim on every JWT Supabase Auth issues.
--
-- Wiring is two-step: this migration defines the function; the project's
-- Auth → Hooks → Custom Access Token setting in the Supabase dashboard must
-- be pointed at `public.custom_access_token_hook`. The function must be
-- executable by the supabase_auth_admin role (which actually runs the hook)
-- and must NOT be executable by anon/authenticated so callers can't probe
-- other users' roles directly.

CREATE FUNCTION public.custom_access_token_hook(event jsonb)
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
  claims := jsonb_set(claims, '{role}', to_jsonb(coalesce(staff_role, 'none')));
  RETURN jsonb_set(event, '{claims}', claims);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.custom_access_token_hook FROM public, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.custom_access_token_hook TO supabase_auth_admin;
