-- 0045_order_messages_test.sql
BEGIN;
SET search_path TO extensions, public;

SELECT plan(3);

SELECT has_table('public', 'order_messages', 'order_messages table exists');
SELECT col_is_pk('public', 'order_messages', 'id', 'id is the PK');
SELECT ok(
  (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.order_messages'::regclass),
  'RLS is enabled on order_messages');

SELECT * FROM finish();
ROLLBACK;
