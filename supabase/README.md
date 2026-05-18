# Supabase backend — Amuwak Staff

This project uses Supabase (Postgres + Auth + Storage) as the backend. PowerSync
sits on top of Supabase to provide bidirectional offline sync to the Flutter app
(see Plan 2). The schema, RLS policies, triggers, storage configuration, and
auth claim hook all live as versioned SQL migrations in `migrations/`.

## Cloud-first workflow

We don't run a local Supabase stack (which would require Docker). Migrations are
pushed directly to a linked remote Supabase project.

### One-time setup

```powershell
supabase login --token <YOUR_PAT>          # personal access token from
                                            # https://supabase.com/dashboard/account/tokens
supabase link --project-ref rrxcsscinwqrxivczrfg
```

Store the database password (shown once at project creation) in `.env.local` at
the repo root — it is gitignored:

```powershell
"SUPABASE_DB_PASSWORD=<your-db-password>" | Out-File -Encoding utf8 .env.local
```

### Applying migrations

```powershell
$env:SUPABASE_DB_PASSWORD = (Get-Content .env.local | Select-String '^SUPABASE_DB_PASSWORD=').Line.Split('=',2)[1]
supabase db push
```

### Running pgTAP tests

```powershell
$env:PGPASSWORD = $env:SUPABASE_DB_PASSWORD
psql "postgresql://postgres.rrxcsscinwqrxivczrfg:$env:PGPASSWORD@aws-0-eu-west-2.pooler.supabase.com:6543/postgres" -f supabase/tests/0001_extensions_test.sql
```

(The pooled connection string is in `supabase/.temp/pooler-url`.)

## Layout

- `migrations/` — versioned schema migrations (lexicographic order).
- `tests/` — pgTAP tests, one per migration. Run via `psql -f` against the linked project.
- `seed.sql` — data inserted on `supabase db push` after migrations run. Currently empty;
  `valid_transitions` is seeded inside migration 0003.

## Conventions

- One concern per migration; never edit a migration once committed. Fix mistakes
  with a follow-up migration.
- Every migration has a sibling `*_test.sql` pgTAP file.
- The anon key is safe to ship in the Flutter app. The `service_role` key never
  leaves Edge Functions or CI.
- The `SUPABASE_DB_PASSWORD` is the **database** password, not the personal
  access token. Both live only in `.env.local` and a password manager.

## Schema design reference

- Spec: [../docs/superpowers/specs/2026-05-18-supabase-backend-design.md](../docs/superpowers/specs/2026-05-18-supabase-backend-design.md)
- Implementation plan: [../docs/superpowers/plans/2026-05-18-supabase-database-foundation.md](../docs/superpowers/plans/2026-05-18-supabase-database-foundation.md)
