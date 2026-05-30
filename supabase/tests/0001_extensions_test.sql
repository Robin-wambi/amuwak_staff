-- 0001_extensions_test.sql
-- Verify that pgcrypto and pgtap are installed and that gen_random_uuid() works.

BEGIN;
SET search_path TO extensions, public;

SELECT plan(2);

SELECT has_extension('pgcrypto');
SELECT isnt(gen_random_uuid()::text, '', 'gen_random_uuid() returns a value');

SELECT * FROM finish();
ROLLBACK;
