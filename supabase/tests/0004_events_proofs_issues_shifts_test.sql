-- 0004_events_proofs_issues_shifts_test.sql
-- Verify the event/proof/issue/shift schema.

BEGIN;
SET search_path TO extensions, public;

SELECT plan(10);

SELECT has_table('public', 'order_status_events', 'order_status_events table exists');
SELECT col_is_unique('public', 'order_status_events', ARRAY['device_event_id'],
  'order_status_events.device_event_id is unique');

SELECT has_table('public', 'proof_events', 'proof_events table exists');
SELECT col_has_check('public', 'proof_events', 'type', 'proof_events.type has CHECK');

SELECT has_index('public', 'proof_events', 'proof_events_one_per_type',
  'partial unique index proof_events_one_per_type exists');

SELECT has_table('public', 'proof_photos', 'proof_photos table exists');
SELECT has_column('public', 'proof_photos', 'storage_path',
  'proof_photos.storage_path exists');
SELECT has_column('public', 'proof_photos', 'uploaded_at',
  'proof_photos.uploaded_at exists');

SELECT has_table('public', 'issues', 'issues table exists');
SELECT has_table('public', 'shifts', 'shifts table exists');

SELECT * FROM finish();
ROLLBACK;
