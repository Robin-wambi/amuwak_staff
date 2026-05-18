-- 0008_storage.sql
-- Storage bucket for pickup/delivery proof photos plus RLS on storage.objects.
--
-- The bucket is private (no anon read). Reads require an authenticated session;
-- writes additionally require the file path to start with the `proof/` prefix
-- so other code can't dump arbitrary content into the bucket. There is no
-- UPDATE or DELETE policy on storage.objects for this bucket — proof photos
-- are immutable from the client side.

INSERT INTO storage.buckets (id, name, public)
VALUES ('proof-photos', 'proof-photos', false)
ON CONFLICT (id) DO NOTHING;

CREATE POLICY proof_photos_read
  ON storage.objects FOR SELECT
  USING (bucket_id = 'proof-photos' AND auth.role() = 'authenticated');

CREATE POLICY proof_photos_write
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'proof-photos'
    AND auth.role() = 'authenticated'
    AND (storage.foldername(name))[1] = 'proof'
  );
