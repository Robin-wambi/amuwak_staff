-- 0013_deferrable_fks.sql
-- Mark every cross-table FK as DEFERRABLE INITIALLY DEFERRED so that PowerSync,
-- when applying a sync batch that touches parent and child tables in arbitrary
-- order inside a single transaction, doesn't raise constraint violations on
-- the temporarily-orphaned intermediate state. Constraint checking happens at
-- COMMIT time for deferred FKs.

ALTER TABLE orders
  ALTER CONSTRAINT orders_customer_id_fkey         DEFERRABLE INITIALLY DEFERRED,
  ALTER CONSTRAINT orders_assigned_driver_fkey     DEFERRABLE INITIALLY DEFERRED,
  ALTER CONSTRAINT orders_intake_recorded_by_fkey  DEFERRABLE INITIALLY DEFERRED,
  ALTER CONSTRAINT orders_created_by_fkey          DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE order_status_events
  ALTER CONSTRAINT order_status_events_order_id_fkey   DEFERRABLE INITIALLY DEFERRED,
  ALTER CONSTRAINT order_status_events_changed_by_fkey DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE proof_events
  ALTER CONSTRAINT proof_events_order_id_fkey    DEFERRABLE INITIALLY DEFERRED,
  ALTER CONSTRAINT proof_events_captured_by_fkey DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE proof_photos
  ALTER CONSTRAINT proof_photos_proof_event_id_fkey DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE issues
  ALTER CONSTRAINT issues_order_id_fkey    DEFERRABLE INITIALLY DEFERRED,
  ALTER CONSTRAINT issues_reported_by_fkey DEFERRABLE INITIALLY DEFERRED,
  ALTER CONSTRAINT issues_resolved_by_fkey DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE shifts
  ALTER CONSTRAINT shifts_staff_id_fkey DEFERRABLE INITIALLY DEFERRED;
