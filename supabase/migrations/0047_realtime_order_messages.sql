-- 0047_realtime_order_messages.sql
-- Customer + staff chat relies on Supabase .stream() for live delivery, which
-- only pushes changes for tables in the supabase_realtime publication. Add
-- order_messages, guarded the same way as 0027 so it's safe to re-run.

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'order_messages'
  ) THEN
    EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE public.order_messages';
  END IF;
END $$;
