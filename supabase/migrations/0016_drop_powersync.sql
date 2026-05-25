-- 0016_drop_powersync.sql
-- Undo migration 0015 after the project pivoted away from PowerSync to a
-- Drift-based offline sync layer (see Plan 2 revised). The powersync role
-- was never given a LOGIN password and the publication was never read, so
-- nothing is using these objects at the time of this drop.
--
-- This migration:
--   1. Drops the powersync publication.
--   2. Revokes all privileges granted to powersync, then drops the role.
--   3. Resets REPLICA IDENTITY to DEFAULT on every table that 0015 set to
--      FULL — DEFAULT is cheaper on WAL volume and is what those tables had
--      before the PowerSync exploration.

DROP PUBLICATION IF EXISTS powersync;

-- Default privileges first (or DROP ROLE will refuse because powersync still
-- owns default privileges).
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  REVOKE SELECT ON TABLES    FROM powersync;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  REVOKE SELECT ON SEQUENCES FROM powersync;

REVOKE SELECT ON ALL TABLES    IN SCHEMA public FROM powersync;
REVOKE SELECT ON ALL SEQUENCES IN SCHEMA public FROM powersync;
REVOKE USAGE  ON SCHEMA public                  FROM powersync;

DROP ROLE IF EXISTS powersync;

ALTER TABLE staff               REPLICA IDENTITY DEFAULT;
ALTER TABLE customers           REPLICA IDENTITY DEFAULT;
ALTER TABLE orders              REPLICA IDENTITY DEFAULT;
ALTER TABLE order_status_events REPLICA IDENTITY DEFAULT;
ALTER TABLE proof_events        REPLICA IDENTITY DEFAULT;
ALTER TABLE proof_photos        REPLICA IDENTITY DEFAULT;
ALTER TABLE issues              REPLICA IDENTITY DEFAULT;
ALTER TABLE shifts              REPLICA IDENTITY DEFAULT;
ALTER TABLE valid_transitions   REPLICA IDENTITY DEFAULT;
