-- 0043_customer_role_hook.sql
-- Extend custom_access_token_hook (0009, fixed in 0025) to issue user_role =
-- 'customer' for a user linked to a customers row, while leaving the staff
-- branch unchanged. Order: staff role wins (a user who is somehow both keeps
-- their staff role); else a linked customer → 'customer'; else 'none'.
--
-- Stays SECURITY DEFINER with the existing restricted grants (CREATE OR REPLACE
-- preserves the 0009 REVOKE-from-public/anon/authenticated + GRANT-to-
-- supabase_auth_admin). Touches only the custom `user_role` claim — never the
-- reserved `role` claim (see 0025).

CREATE OR REPLACE FUNCTION public.custom_access_token_hook(event jsonb)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  claims      jsonb;
  staff_role  text;
  is_customer boolean;
  resolved    text;
BEGIN
  SELECT role INTO staff_role FROM public.staff
   WHERE id = (event->>'user_id')::uuid AND active = true;

  IF staff_role IS NOT NULL THEN
    resolved := staff_role;
  ELSE
    SELECT EXISTS (
      SELECT 1 FROM public.customers
       WHERE auth_user_id = (event->>'user_id')::uuid AND deleted_at IS NULL
    ) INTO is_customer;
    resolved := CASE WHEN is_customer THEN 'customer' ELSE 'none' END;
  END IF;

  claims := event->'claims';
  claims := jsonb_set(claims, '{user_role}', to_jsonb(resolved));
  RETURN jsonb_set(event, '{claims}', claims);
END;
$$;
