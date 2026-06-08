-- 0020_pricing_settings_updated_by_on_delete.sql
-- Make pricing_settings.updated_by non-blocking on staff deletion.
--
-- Migration 0019 declared `updated_by uuid REFERENCES staff(id)` with no
-- ON DELETE clause, so Postgres defaults to NO ACTION (RESTRICT): hard-deleting
-- the staff member who last saved the global rate would fail with a FK
-- violation. updated_by is an audit pointer, not an ownership link, so SET NULL
-- is the right behaviour — the reference clears and the delete proceeds.

ALTER TABLE pricing_settings
  DROP CONSTRAINT pricing_settings_updated_by_fkey,
  ADD CONSTRAINT pricing_settings_updated_by_fkey
    FOREIGN KEY (updated_by) REFERENCES staff(id) ON DELETE SET NULL;
