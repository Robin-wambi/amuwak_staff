-- 0029_orders_audit_columns.sql
-- Audit pointers for order mutations after creation:
--   * updated_by — the staff member who last edited an order's descriptive or
--     status fields (the card "Edit details" / "Mark as ..." flows).
--   * deleted_by — the staff member who soft-deleted (tombstoned) an order.
--
-- Mirrors pricing_settings.updated_by (migrations 0019/0020): these are audit
-- pointers, not ownership links, so a hard-deleted staff member clears the
-- reference (ON DELETE SET NULL) rather than blocking the delete with a FK
-- violation. Both columns are nullable so historical rows stay valid.
--
-- No RLS change is needed: orders_update (migration 0010) gates UPDATEs by role
-- and driver assignment, not by individual columns, so writing these audit
-- columns is already covered for in_shop/manager (and a driver on their own
-- assigned order).

ALTER TABLE orders
  ADD COLUMN updated_by uuid REFERENCES staff(id) ON DELETE SET NULL,
  ADD COLUMN deleted_by uuid REFERENCES staff(id) ON DELETE SET NULL;
