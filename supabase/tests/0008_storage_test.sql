-- 0008_storage_test.sql
-- Verify the proof-photos bucket exists, is private, and has its read policy.

BEGIN;
SET search_path TO extensions, public;

SELECT plan(3);

SELECT is(
  (SELECT count(*) FROM storage.buckets WHERE id = 'proof-photos')::int,
  1, 'proof-photos bucket exists');

SELECT is(
  (SELECT public FROM storage.buckets WHERE id = 'proof-photos'),
  false, 'proof-photos bucket is private');

SELECT is(
  (SELECT count(*) FROM pg_policies
   WHERE schemaname = 'storage' AND tablename = 'objects'
     AND policyname = 'proof_photos_read')::int,
  1, 'proof_photos_read policy exists on storage.objects');

SELECT * FROM finish();
ROLLBACK;
