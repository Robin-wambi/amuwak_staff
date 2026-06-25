-- 0027_enable_realtime_publication.sql
-- Online-only reads use Supabase `.stream(primaryKey: ['id'])` (see
-- lib/src/sync/orders_repository.dart, proof_events_repository.dart). A stream
-- loads an initial snapshot via a plain select but only delivers *live* changes
-- for tables that are members of the `supabase_realtime` publication. Without
-- membership the write succeeds yet the dashboard never reflects it in-session
-- (edits/new pickups/proof captures appear to save but don't show), and the
-- new-pickup -> pickup-capture auto-advance never fires.
--
-- This was previously a manual ops step (docs/online-only-mode.md) that was
-- easy to miss when standing up an environment. Baking it into a migration
-- makes it reproducible across prod/staging/dev.
--
-- Idempotent and guarded: `ALTER PUBLICATION ... ADD TABLE` errors if the table
-- is already a member, so each add is skipped when the table is present. That
-- keeps the migration safe to run against environments where the publication
-- was already configured by hand. The table list mirrors the five read tables
-- documented in docs/online-only-mode.md (proof_photos is intentionally absent
-- — proof capture writes proof_events, which is included).

DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'orders', 'customers', 'proof_events', 'staff', 'order_status_events'
  ] LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime'
        AND schemaname = 'public'
        AND tablename = t
    ) THEN
      EXECUTE format(
        'ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', t);
    END IF;
  END LOOP;
END $$;
