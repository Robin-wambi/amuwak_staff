-- 0015_powersync_replication_test.sql
-- Verify the Postgres-side scaffolding PowerSync needs: a dedicated role with
-- REPLICATION + BYPASSRLS, a publication that names every synced table, and
-- REPLICA IDENTITY FULL on each synced table.

BEGIN;
SET search_path TO extensions, public;

SELECT plan(8);

-- 1. Role exists
SELECT has_role('powersync', 'powersync role exists');

-- 2. Role has REPLICATION
SELECT is(
  (SELECT rolreplication FROM pg_roles WHERE rolname = 'powersync'),
  true, 'powersync role has REPLICATION privilege');

-- 3. Role has BYPASSRLS so RLS does not filter the replication stream
SELECT is(
  (SELECT rolbypassrls FROM pg_roles WHERE rolname = 'powersync'),
  true, 'powersync role has BYPASSRLS');

-- 4. Role is NOLOGIN until the user sets a password manually
SELECT is(
  (SELECT rolcanlogin FROM pg_roles WHERE rolname = 'powersync'),
  false, 'powersync role starts as NOLOGIN (password set manually post-migration)');

-- 5. Publication exists
SELECT is(
  (SELECT count(*) FROM pg_publication WHERE pubname = 'powersync')::int,
  1, 'publication powersync exists');

-- 6. Publication includes orders
SELECT is(
  (SELECT count(*) FROM pg_publication_tables
   WHERE pubname = 'powersync' AND tablename = 'orders')::int,
  1, 'publication includes orders');

-- 7. orders has REPLICA IDENTITY FULL  ('f' in relreplident)
SELECT is(
  (SELECT relreplident::text FROM pg_class
   WHERE oid = 'public.orders'::regclass),
  'f', 'orders REPLICA IDENTITY is FULL');

-- 8. proof_events has REPLICA IDENTITY FULL
SELECT is(
  (SELECT relreplident::text FROM pg_class
   WHERE oid = 'public.proof_events'::regclass),
  'f', 'proof_events REPLICA IDENTITY is FULL');

SELECT * FROM finish();
ROLLBACK;
