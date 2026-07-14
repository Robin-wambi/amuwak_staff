-- 0047_realtime_order_messages_test.sql
BEGIN;
SET search_path TO extensions, public;

SELECT plan(1);

SELECT ok(
  EXISTS (SELECT 1 FROM pg_publication_tables
          WHERE pubname = 'supabase_realtime'
            AND schemaname = 'public'
            AND tablename = 'order_messages'),
  'order_messages is in the supabase_realtime publication');

SELECT * FROM finish();
ROLLBACK;
