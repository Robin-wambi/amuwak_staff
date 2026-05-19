-- 0016_drop_powersync_test.sql
-- Verify that migration 0016 reverted the PowerSync-related artifacts from
-- migration 0015: role gone, publication gone, REPLICA IDENTITY back to
-- DEFAULT on every previously-affected table.

BEGIN;
SET search_path TO extensions, public;

SELECT plan(11);

-- Role and publication are gone
SELECT is(
  (SELECT count(*) FROM pg_roles WHERE rolname = 'powersync')::int,
  0, 'powersync role no longer exists');

SELECT is(
  (SELECT count(*) FROM pg_publication WHERE pubname = 'powersync')::int,
  0, 'publication powersync no longer exists');

-- REPLICA IDENTITY back to DEFAULT ('d') on every table 0015 had set to FULL.
-- relreplident is the "char" type (single byte); cast to text for pgTAP.
SELECT is((SELECT relreplident::text FROM pg_class WHERE oid='public.staff'::regclass),               'd', 'staff REPLICA IDENTITY is DEFAULT');
SELECT is((SELECT relreplident::text FROM pg_class WHERE oid='public.customers'::regclass),           'd', 'customers REPLICA IDENTITY is DEFAULT');
SELECT is((SELECT relreplident::text FROM pg_class WHERE oid='public.orders'::regclass),              'd', 'orders REPLICA IDENTITY is DEFAULT');
SELECT is((SELECT relreplident::text FROM pg_class WHERE oid='public.order_status_events'::regclass), 'd', 'order_status_events REPLICA IDENTITY is DEFAULT');
SELECT is((SELECT relreplident::text FROM pg_class WHERE oid='public.proof_events'::regclass),        'd', 'proof_events REPLICA IDENTITY is DEFAULT');
SELECT is((SELECT relreplident::text FROM pg_class WHERE oid='public.proof_photos'::regclass),        'd', 'proof_photos REPLICA IDENTITY is DEFAULT');
SELECT is((SELECT relreplident::text FROM pg_class WHERE oid='public.issues'::regclass),              'd', 'issues REPLICA IDENTITY is DEFAULT');
SELECT is((SELECT relreplident::text FROM pg_class WHERE oid='public.shifts'::regclass),              'd', 'shifts REPLICA IDENTITY is DEFAULT');
SELECT is((SELECT relreplident::text FROM pg_class WHERE oid='public.valid_transitions'::regclass),   'd', 'valid_transitions REPLICA IDENTITY is DEFAULT');

SELECT * FROM finish();
ROLLBACK;
