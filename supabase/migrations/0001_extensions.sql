-- 0001_extensions.sql
-- Enable extensions required by the rest of the schema and by pgTAP tests.
-- All extensions live in the dedicated `extensions` schema (Supabase convention).

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pgtap    WITH SCHEMA extensions;
