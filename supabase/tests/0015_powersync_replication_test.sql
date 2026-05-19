-- 0015_powersync_replication_test.sql
-- Verify the Postgres-side scaffolding PowerSync needs: a dedicated role with
-- REPLICATION + BYPASSRLS, a publication that names every synced table, and
-- REPLICA IDENTITY FULL on each synced table.

BEGIN;
SET search_path TO extensions, public;

SELECT plan(15);

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

-- 7-15. Every synced table has REPLICA IDENTITY FULL ('f' in relreplident).
-- relreplident is the "char" type (single byte); cast to text for pgTAP.
SELECT is((SELECT relreplident::text FROM pg_class WHERE oid='public.staff'::regclass),               'f', 'staff REPLICA IDENTITY is FULL');
SELECT is((SELECT relreplident::text FROM pg_class WHERE oid='public.customers'::regclass),           'f', 'customers REPLICA IDENTITY is FULL');
SELECT is((SELECT relreplident::text FROM pg_class WHERE oid='public.orders'::regclass),              'f', 'orders REPLICA IDENTITY is FULL');
SELECT is((SELECT relreplident::text FROM pg_class WHERE oid='public.order_status_events'::regclass), 'f', 'order_status_events REPLICA IDENTITY is FULL');
SELECT is((SELECT relreplident::text FROM pg_class WHERE oid='public.proof_events'::regclass),        'f', 'proof_events REPLICA IDENTITY is FULL');
SELECT is((SELECT relreplident::text FROM pg_class WHERE oid='public.proof_photos'::regclass),        'f', 'proof_photos REPLICA IDENTITY is FULL');
SELECT is((SELECT relreplident::text FROM pg_class WHERE oid='public.issues'::regclass),              'f', 'issues REPLICA IDENTITY is FULL');
SELECT is((SELECT relreplident::text FROM pg_class WHERE oid='public.shifts'::regclass),              'f', 'shifts REPLICA IDENTITY is FULL');
SELECT is((SELECT relreplident::text FROM pg_class WHERE oid='public.valid_transitions'::regclass),   'f', 'valid_transitions REPLICA IDENTITY is FULL');

SELECT * FROM finish();
ROLLBACK;
