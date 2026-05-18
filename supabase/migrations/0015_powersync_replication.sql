-- 0015_powersync_replication.sql
-- PowerSync prerequisites on the Postgres side. The role is created NOLOGIN —
-- the operator gives it a password manually via the Supabase SQL editor and
-- pastes that password into the PowerSync dashboard. This keeps the
-- credential out of git.
--
-- BYPASSRLS is intentional: PowerSync needs to see every row in order to
-- compute bucket membership per sync rules. Per-user filtering happens in
-- powersync/sync-rules.yaml, not in Postgres RLS.

CREATE ROLE powersync WITH REPLICATION BYPASSRLS NOLOGIN;

-- Read access on the public schema so PowerSync can take initial snapshots.
GRANT USAGE ON SCHEMA public TO powersync;
GRANT SELECT ON ALL TABLES    IN SCHEMA public TO powersync;
GRANT SELECT ON ALL SEQUENCES IN SCHEMA public TO powersync;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT ON TABLES    TO powersync;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT ON SEQUENCES TO powersync;

-- Publication: enumerate the tables we want PowerSync to replicate. We
-- deliberately do NOT use FOR ALL TABLES — that would also publish
-- supabase_migrations.schema_migrations and other infrastructure tables,
-- which we don't want to sync.
CREATE PUBLICATION powersync FOR TABLE
  staff,
  customers,
  orders,
  order_status_events,
  proof_events,
  proof_photos,
  issues,
  shifts,
  valid_transitions;

-- Replica identity FULL on every synced table so PowerSync sees the full
-- pre-/post-image for each change (required for diff-based sync).
ALTER TABLE staff               REPLICA IDENTITY FULL;
ALTER TABLE customers           REPLICA IDENTITY FULL;
ALTER TABLE orders              REPLICA IDENTITY FULL;
ALTER TABLE order_status_events REPLICA IDENTITY FULL;
ALTER TABLE proof_events        REPLICA IDENTITY FULL;
ALTER TABLE proof_photos        REPLICA IDENTITY FULL;
ALTER TABLE issues              REPLICA IDENTITY FULL;
ALTER TABLE shifts              REPLICA IDENTITY FULL;
ALTER TABLE valid_transitions   REPLICA IDENTITY FULL;
