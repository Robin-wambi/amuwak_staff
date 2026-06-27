-- 0030_set_my_display_name_not_found.sql
-- Supersedes the function body created in 0028: add a NOT FOUND guard.
--
-- 0028's UPDATE silently affects 0 rows when the caller has no active staff row
-- (e.g. deactivated mid-session while holding a valid JWT). The RPC then returns
-- void as if it succeeded, and the client moves on to set the password while the
-- name change was quietly dropped. Raise instead so the caller surfaces an error.
--
-- This is an append-only fix (CREATE OR REPLACE in a new migration) rather than
-- an edit to 0028: 0028 is already applied in some environments, and Supabase
-- tracks migrations by version, so an in-place edit would never re-run there.
-- A new migration converges every environment through the normal runner.

CREATE OR REPLACE FUNCTION set_my_display_name(new_name text) RETURNS void
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = public AS $$
BEGIN
  IF coalesce(trim(new_name), '') = '' THEN
    RAISE EXCEPTION 'Display name is required';
  END IF;
  UPDATE staff SET display_name = trim(new_name)
  WHERE id = auth.uid() AND active = true;
  -- No active row for the caller: fail loudly so the client surfaces an error
  -- instead of silently dropping the name change.
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Staff record not found or inactive';
  END IF;
END $$;
