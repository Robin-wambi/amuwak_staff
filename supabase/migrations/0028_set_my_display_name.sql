-- 0028_set_my_display_name.sql
-- Let a signed-in staff member set their OWN display name (used during invite
-- onboarding on the Set-password screen).
--
-- RLS on staff only allows managers to write (staff_manager_write, 0007), so a
-- newly-invited driver/in_shop user cannot update their own row directly. A
-- blanket self-update RLS policy is unsafe: RLS can't restrict columns, so it
-- would also let users change their own role/active. Instead expose a narrow,
-- column-scoped SECURITY DEFINER function — same house style as auth_staff_role()
-- in 0007 — that only ever touches display_name on the caller's own active row.

CREATE FUNCTION set_my_display_name(new_name text) RETURNS void
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = public AS $$
BEGIN
  IF coalesce(trim(new_name), '') = '' THEN
    RAISE EXCEPTION 'Display name is required';
  END IF;
  UPDATE staff SET display_name = trim(new_name)
  WHERE id = auth.uid() AND active = true;
END $$;

REVOKE EXECUTE ON FUNCTION set_my_display_name(text) FROM public;
GRANT  EXECUTE ON FUNCTION set_my_display_name(text) TO authenticated;
