# Supabase backend — Amuwak Staff

Supabase (Postgres + Auth + Storage) is the backend. Bidirectional offline
sync to the Flutter app is handled by the in-app outbox + watermarked puller
(see Plan 2); PowerSync was evaluated and dropped in migration `0016`.
The schema, RLS policies, triggers, storage configuration, and auth claim hook
all live as versioned SQL migrations in `migrations/`.

## Cloud-first workflow

No local Supabase stack (no Docker). Migrations are pushed directly to the
linked remote project: `rrxcsscinwqrxivczrfg` (region eu-west-2).

### One-time setup

```powershell
supabase login --token <YOUR_PAT>                    # personal access token from
                                                     # https://supabase.com/dashboard/account/tokens
supabase link --project-ref rrxcsscinwqrxivczrfg
```

Store the database password in `.env.local` at the repo root — gitignored:

```
SUPABASE_DB_PASSWORD=<your-db-password>
```

If you created the file in PowerShell, make sure it has no UTF-8 BOM. To verify,
`xxd .env.local | head -1` should start with `5355 5041` (the ASCII for `SUPA…`),
not `EFBB BF…`.

### Manual step: enable the auth claim hook

Migration `0009_auth_claim_hook.sql` defines the function but Supabase's auth
service only picks it up after it is wired through the dashboard:

1. Open `https://supabase.com/dashboard/project/rrxcsscinwqrxivczrfg/auth/hooks`
2. Find **Custom Access Token** → **Add a new hook**.
3. Hook type: **Postgres**, schema: `public`, function: `custom_access_token_hook`.
4. Save. Sign out and back in once so a new JWT is issued with the `role` claim.

### Applying migrations

```powershell
# Once per session, expose the password to the supabase CLI:
$env:SUPABASE_DB_PASSWORD = (Select-String '^SUPABASE_DB_PASSWORD=' .env.local).Line.Split('=',2)[1]
supabase db push
```

### Deploy order: push migrations BEFORE merging app code that depends on them

Migrations are applied manually (above); the PWA auto-deploys on every push to
`main` (`.github/workflows/deploy-pwa.yml`). The DB password never goes into CI,
so the two steps can't be coupled there — sequencing is on us.

The rule: **`supabase db push` first, then merge.** App code that calls a new
function/table will fail until the migration is live. New migrations are
additive and backward-compatible (old app builds don't reference the new
objects), so applying them to production ahead of the merge is safe and carries
no risk to the running app.

Concretely, for `0017` (the `next_order_code()` RPC that order creation calls):

1. `supabase db push` — adds the counter table + function (nothing calls it yet).
2. Verify: `select next_order_code();` returns `AMW-<year>-0001`.
3. Merge the PR → the PWA redeploys with the RPC already live.

If step 1 is skipped, order creation surfaces a retryable "Could not reserve an
order number" error (not a crash), but riders are blocked until the migration is
applied.

### Running pgTAP tests

The pooled connection string is in `supabase/.temp/pooler-url`. To run a single
test file:

```powershell
$env:PGPASSWORD = $env:SUPABASE_DB_PASSWORD
psql "postgresql://postgres.rrxcsscinwqrxivczrfg@aws-1-eu-west-2.pooler.supabase.com:5432/postgres" `
  -f supabase/tests/0001_extensions_test.sql
```

To run every test in order:

```powershell
Get-ChildItem supabase/tests/*.sql | Sort-Object Name | ForEach-Object {
  Write-Host "=== $($_.Name) ==="
  psql "postgresql://postgres.rrxcsscinwqrxivczrfg@aws-1-eu-west-2.pooler.supabase.com:5432/postgres" -f $_.FullName
}
```

## Layout

Selected highlights below — see `migrations/` for the complete, authoritative
list (e.g. `0010`–`0016` cover RLS tightening, trigger security, and the
PowerSync exploration/rollback).

| Path                    | Purpose                                                   |
|-------------------------|-----------------------------------------------------------|
| `migrations/0001_…`     | Enable pgcrypto + pgtap                                   |
| `migrations/0002_…`     | `staff`, `customers`                                      |
| `migrations/0003_…`     | `orders`, `valid_transitions` + seed (31 rows)            |
| `migrations/0004_…`     | `order_status_events`, `proof_events`, `proof_photos`, `issues`, `shifts` |
| `migrations/0005_…`     | `set_updated_at()` + `validate_status_transition()` triggers |
| `migrations/0006_…`     | Hotfix: switch `set_updated_at()` to `clock_timestamp()`  |
| `migrations/0007_…`     | RLS helper + per-table policies                           |
| `migrations/0008_…`     | `proof-photos` storage bucket + RLS                       |
| `migrations/0009_…`     | `custom_access_token_hook` for staff role claim           |
| `migrations/0017_…`     | `order_code_counters` + `next_order_code()` RPC (sequential `AMW-YYYY-NNNN` codes) |
| `migrations/0018_…`     | `next_order_code()` reconciles the counter against the max existing `order_code` (self-heals a stale counter) |
| `tests/`                | Sibling pgTAP test per migration                          |
| `seed.sql`              | (Empty placeholder — seeds embedded in migrations.)       |

## Conventions

- One concern per migration; never edit a migration once committed. Fix
  mistakes with a follow-up migration (e.g. `0006` corrects `0005`).
- Every migration has a sibling `*_test.sql` pgTAP file.
- The Supabase **anon key** is safe to ship in the Flutter app. The
  **service_role key** and the **database password** never leave the
  developer's machine, Edge Functions, or CI.
- Migration filenames must be either a timestamp or numeric (`NNNN_name.sql`).
  The Supabase CLI rejects names like `0005a_…`.
- `SUPABASE_DB_PASSWORD` is the **database** password, not the personal access
  token. Both live only in `.env.local` and a password manager.

## Reference docs

- Spec: [../docs/superpowers/specs/2026-05-18-supabase-backend-design.md](../docs/superpowers/specs/2026-05-18-supabase-backend-design.md)
- Implementation plan: [../docs/superpowers/plans/2026-05-18-supabase-database-foundation.md](../docs/superpowers/plans/2026-05-18-supabase-database-foundation.md)
