-- 0027_enable_realtime_publication_test.sql
-- Verifies the five read tables the online-only app streams from are members of
-- the `supabase_realtime` publication, so a write reflects live in-session
-- instead of silently showing the pre-write snapshot. Runs inside
-- BEGIN ... ROLLBACK so nothing touches real data.

BEGIN;
SET search_path TO extensions, public;

SELECT plan(5);

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'orders'),
  'orders is a member of supabase_realtime');

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'customers'),
  'customers is a member of supabase_realtime');

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'proof_events'),
  'proof_events is a member of supabase_realtime');

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'staff'),
  'staff is a member of supabase_realtime');

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'order_status_events'),
  'order_status_events is a member of supabase_realtime');

SELECT * FROM finish();
ROLLBACK;
