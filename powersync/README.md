# PowerSync setup — Amuwak Staff

PowerSync provides bidirectional offline sync between the Supabase Postgres
project (`rrxcsscinwqrxivczrfg`) and the Flutter app. The instance is
operated through the PowerSync cloud dashboard; this directory holds the
declarative artifacts (sync rules) that are version-controlled.

## Layout

| File              | Purpose                                                |
|-------------------|--------------------------------------------------------|
| `sync-rules.yaml` | Bucket definitions deployed to the PowerSync instance. |
| `README.md`       | This file — setup and operational runbook.             |

## One-time setup

1. Apply Supabase migration `0015_powersync_replication.sql` (see `../supabase/`)
   if it isn't already applied. Verify with:

   ```powershell
   $env:PGPASSWORD = (Select-String '^SUPABASE_DB_PASSWORD=' .env.local).Line.Split('=',2)[1]
   psql "postgresql://postgres.rrxcsscinwqrxivczrfg@aws-1-eu-west-2.pooler.supabase.com:5432/postgres" `
     -f supabase/tests/0015_powersync_replication_test.sql
   ```

   Expected: 15/15 pgTAP assertions pass.

2. In the Supabase SQL editor
   (https://supabase.com/dashboard/project/rrxcsscinwqrxivczrfg/sql/new),
   set a password on the `powersync` role and grant it LOGIN:

   ```sql
   -- Generate one in PowerShell beforehand:
   --   -join ((48..57)+(65..90)+(97..122)+(33,35,36,37,38,42,43) `
   --       | Get-Random -Count 40 | ForEach-Object { [char]$_ })
   ALTER ROLE powersync WITH LOGIN PASSWORD '<GENERATED_PASSWORD>';
   ```

   **Store the password in a password manager immediately.** It is not
   recoverable from Postgres later. Treat it like a service_role key.

3. Sign up for PowerSync at
   https://accounts.journeyapps.com/portal/free-trial. Create an instance:
   name `amuwak-staff-dev`, region eu-west-1 (closest to the Supabase
   eu-west-2 region).

4. Connect to Supabase Postgres. PowerSync dashboard → instance →
   **Database connections** → **Add connection** → **Postgres**:

   | Field        | Value                                              |
   |--------------|----------------------------------------------------|
   | Host         | `aws-1-eu-west-2.pooler.supabase.com`              |
   | Port         | `5432`                                             |
   | Database     | `postgres`                                         |
   | Username     | `powersync.rrxcsscinwqrxivczrfg`                   |
   | Password     | (the password set in step 2)                       |
   | Publication  | `powersync`                                        |
   | Slot name    | `powersync`                                        |
   | SSL          | required                                           |

   Save. The connection status should turn green within ~30 seconds.

5. Add JWKS auth so PowerSync trusts Supabase-issued JWTs. PowerSync
   instance → **Auth** → **Add JWKS URI**:

   - JWKS URI: `https://rrxcsscinwqrxivczrfg.supabase.co/auth/v1/.well-known/jwks.json`
   - Audience: `authenticated`
   - Issuer:   `https://rrxcsscinwqrxivczrfg.supabase.co/auth/v1`

6. Upload `sync-rules.yaml` to the instance → **Validate** → **Deploy**.
   The dashboard should report three buckets: `reference`, `driver`,
   `shop_full`.

7. Capture the instance endpoint URL (PowerSync dashboard → **Endpoint**,
   looks like `https://<instance-id>.powersync.journeyapps.com`). The
   Flutter app (Plan 3) reads it via `--dart-define=POWERSYNC_URL=…`.

## Updating sync rules

1. Edit `sync-rules.yaml`. Commit.
2. PowerSync dashboard → **Sync rules** → paste new content → **Validate** →
   **Deploy**.
3. The instance redeploys; existing clients reconnect and replay buckets.

Sync rules are **not** auto-deployed from this repo — the dashboard is the
runtime source of truth. Keep them in sync by reviewing diffs in code review.

## Buckets

| Bucket      | Membership                                     | Contents                                                                       |
|-------------|------------------------------------------------|--------------------------------------------------------------------------------|
| `reference` | Every signed-in staff member                   | `valid_transitions`, `staff` list (minus PINs), `customers` (non-deleted)      |
| `driver`    | `role='driver'`, scoped to `request.user_id()` | Their orders (assigned or unassigned), descendants, their own issues + shifts  |
| `shop_full` | `role IN ('in_shop','manager')`                | All non-deleted orders, all status events, all proof events + photos, all issues, all shifts |

## Rotating the `powersync` Postgres password

1. Generate a new password.
2. In the Supabase SQL editor:
   ```sql
   ALTER ROLE powersync WITH PASSWORD '<NEW_PASSWORD>';
   ```
3. PowerSync dashboard → instance → **Database connections** → edit the
   connection → paste the new password → save. The instance will reconnect.

## Operational notes

- The `powersync` Postgres role has `BYPASSRLS`. Sync rules do all per-user
  filtering — RLS does not apply to the replication stream. Once the LOGIN
  password is set, anyone holding it can SELECT every row of every public
  table directly. Keep the credential tightly controlled.
- Free tier limit: one instance, ~10 concurrent clients. Plenty for pilot
  scale.
- If the replication slot lags (instance disconnected for a long stretch),
  Postgres WAL grows. Reconnect promptly; if the slot becomes unrecoverable,
  drop it on the Postgres side and let PowerSync recreate it:
  ```sql
  SELECT pg_drop_replication_slot('powersync');
  ```
  PowerSync will recreate the slot on its next connection attempt and take a
  fresh initial snapshot of every table in the publication.

## Reference docs

- PowerSync × Supabase integration guide:
  https://docs.powersync.com/integration-guides/supabase
- Spec: [../docs/superpowers/specs/2026-05-18-supabase-backend-design.md](../docs/superpowers/specs/2026-05-18-supabase-backend-design.md)
- Plan 2: [../docs/superpowers/plans/2026-05-19-powersync-sync-layer.md](../docs/superpowers/plans/2026-05-19-powersync-sync-layer.md)
