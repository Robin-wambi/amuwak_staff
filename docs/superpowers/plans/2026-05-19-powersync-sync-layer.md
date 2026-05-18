# PowerSync Sync Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up PowerSync as the offline-sync layer on top of the Supabase project from Plan 1, with a published Postgres replication stream and a deployed `sync-rules.yaml` that routes data to drivers, in-shop staff, and managers.

**Architecture:** PowerSync runs as a managed service that connects to Supabase's Postgres via logical replication. A dedicated `powersync` DB role (REPLICATION + BYPASSRLS) reads from a publication that includes every synced table. Each table has `REPLICA IDENTITY FULL` so PowerSync sees the full pre-/post-image for diffing. Sync rules in YAML select bucket membership per JWT claim (`role`, `sub`); the Flutter SDK (Plan 3) reads from those buckets. Authentication is bridged by validating Supabase-issued JWTs against Supabase's JWKS URL — no separate token issuer.

**Tech Stack:** PowerSync Cloud (free tier), Postgres logical replication, Supabase Auth JWTs.

**Source spec:** [../specs/2026-05-18-supabase-backend-design.md](../specs/2026-05-18-supabase-backend-design.md)
**Prerequisite plan:** [2026-05-18-supabase-database-foundation.md](2026-05-18-supabase-database-foundation.md) (must be merged + applied; the `custom_access_token_hook` from migration 0009 must be wired in the Supabase dashboard so JWTs carry the `role` claim).

---

## Task 1: Migration 0015 — powersync DB role, publication, replica identity

**Files:**
- Create: `supabase/migrations/0015_powersync_replication.sql`
- Create: `supabase/tests/0015_powersync_replication_test.sql`

- [ ] **Step 1: Write the failing test**

Create `supabase/tests/0015_powersync_replication_test.sql`:

```sql
-- 0015_powersync_replication_test.sql
-- Verify the Postgres-side scaffolding PowerSync needs: a dedicated role with
-- REPLICATION + BYPASSRLS, a publication that names every synced table, and
-- REPLICA IDENTITY FULL on each synced table.

BEGIN;
SET search_path TO extensions, public;

SELECT plan(8);

-- 1. Role exists
SELECT has_role('powersync', 'powersync role exists');

-- 2. Role has REPLICATION
SELECT is(
  (SELECT rolreplication FROM pg_roles WHERE rolname = 'powersync'),
  true, 'powersync role has REPLICATION privilege');

-- 3. Role has BYPASSRLS so RLS does not filter the replication stream
SELECT is(
  (SELECT rolbypassrls FROM pg_roles WHERE rolname = 'powersync'),
  true, 'powersync role has BYPASSRLS');

-- 4. Role is NOLOGIN until the user sets a password manually
SELECT is(
  (SELECT rolcanlogin FROM pg_roles WHERE rolname = 'powersync'),
  false, 'powersync role starts as NOLOGIN (password set manually post-migration)');

-- 5. Publication exists
SELECT is(
  (SELECT count(*) FROM pg_publication WHERE pubname = 'powersync')::int,
  1, 'publication powersync exists');

-- 6. Publication includes orders
SELECT is(
  (SELECT count(*) FROM pg_publication_tables
   WHERE pubname = 'powersync' AND tablename = 'orders')::int,
  1, 'publication includes orders');

-- 7. orders has REPLICA IDENTITY FULL  ('f' in relreplident)
SELECT is(
  (SELECT relreplident::text FROM pg_class
   WHERE oid = 'public.orders'::regclass),
  'f', 'orders REPLICA IDENTITY is FULL');

-- 8. proof_events has REPLICA IDENTITY FULL
SELECT is(
  (SELECT relreplident::text FROM pg_class
   WHERE oid = 'public.proof_events'::regclass),
  'f', 'proof_events REPLICA IDENTITY is FULL');

SELECT * FROM finish();
ROLLBACK;
```

- [ ] **Step 2: Run the test — confirm failure**

```powershell
$env:PGPASSWORD = (Select-String '^SUPABASE_DB_PASSWORD=' .env.local).Line.Split('=',2)[1]
psql "postgresql://postgres.rrxcsscinwqrxivczrfg@aws-1-eu-west-2.pooler.supabase.com:5432/postgres" `
  -f supabase/tests/0015_powersync_replication_test.sql
```

Expected: all 8 assertions fail — the role, publication, and replica identity haven't been created yet.

- [ ] **Step 3: Write the migration**

Create `supabase/migrations/0015_powersync_replication.sql`:

```sql
-- 0015_powersync_replication.sql
-- PowerSync prerequisites on the Postgres side. The role is created NOLOGIN —
-- the operator gives it a password manually via the Supabase SQL editor and
-- pastes that password into the PowerSync dashboard. This keeps the
-- credential out of git.
--
-- BYPASSRLS is intentional: PowerSync needs to see every row in order to
-- compute bucket membership per sync rules. Per-user filtering happens in
-- powersync/sync-rules.yaml, not in Postgres RLS.

CREATE ROLE powersync WITH REPLICATION BYPASSRLS NOLOGIN;

-- Read access on the public schema so PowerSync can take initial snapshots.
GRANT USAGE ON SCHEMA public TO powersync;
GRANT SELECT ON ALL TABLES    IN SCHEMA public TO powersync;
GRANT SELECT ON ALL SEQUENCES IN SCHEMA public TO powersync;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT ON TABLES    TO powersync;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT ON SEQUENCES TO powersync;

-- Publication: enumerate the tables we want PowerSync to replicate. We
-- deliberately do NOT use FOR ALL TABLES — that would also publish
-- supabase_migrations.schema_migrations and other infrastructure tables,
-- which we don't want to sync.
CREATE PUBLICATION powersync FOR TABLE
  staff,
  customers,
  orders,
  order_status_events,
  proof_events,
  proof_photos,
  issues,
  shifts,
  valid_transitions;

-- Replica identity FULL on every synced table so PowerSync sees the full
-- pre-/post-image for each change (required for diff-based sync).
ALTER TABLE staff               REPLICA IDENTITY FULL;
ALTER TABLE customers           REPLICA IDENTITY FULL;
ALTER TABLE orders              REPLICA IDENTITY FULL;
ALTER TABLE order_status_events REPLICA IDENTITY FULL;
ALTER TABLE proof_events        REPLICA IDENTITY FULL;
ALTER TABLE proof_photos        REPLICA IDENTITY FULL;
ALTER TABLE issues              REPLICA IDENTITY FULL;
ALTER TABLE shifts              REPLICA IDENTITY FULL;
ALTER TABLE valid_transitions   REPLICA IDENTITY FULL;
```

- [ ] **Step 4: Push the migration**

```powershell
$env:SUPABASE_DB_PASSWORD = (Select-String '^SUPABASE_DB_PASSWORD=' .env.local).Line.Split('=',2)[1]
supabase db push --yes
```

Expected: `Applying migration 0015_powersync_replication.sql... Finished supabase db push.`

- [ ] **Step 5: Re-run the test — confirm pass**

```powershell
$env:PGPASSWORD = $env:SUPABASE_DB_PASSWORD
psql "postgresql://postgres.rrxcsscinwqrxivczrfg@aws-1-eu-west-2.pooler.supabase.com:5432/postgres" `
  -f supabase/tests/0015_powersync_replication_test.sql
```

Expected: 8/8 pgTAP assertions pass.

- [ ] **Step 6: Commit**

```powershell
git add supabase/migrations/0015_powersync_replication.sql `
        supabase/tests/0015_powersync_replication_test.sql
git commit -m "Add migration 0015: powersync role, publication, replica identity"
```

---

## Task 2: sync-rules.yaml

**Files:**
- Create: `powersync/sync-rules.yaml`

- [ ] **Step 1: Create the powersync directory**

```powershell
New-Item -ItemType Directory -Path powersync -Force | Out-Null
```

- [ ] **Step 2: Write the sync rules**

Create `powersync/sync-rules.yaml`:

```yaml
# PowerSync sync rules for Amuwak Staff.
#
# Buckets define which subset of rows a given client sees. Membership is
# computed from the JWT claims that Supabase Auth attaches to every session:
#   - request.user_id()  → 'sub' claim  (the staff UUID)
#   - request.jwt() ->> 'role'  → 'driver' | 'in_shop' | 'manager' | 'none'
#     (injected by the custom_access_token_hook in supabase migration 0009)
#
# Three buckets:
#   reference  — global lookup tables, visible to every signed-in user
#   driver     — per-driver slice: only their orders + descendants
#   shop_full  — full data set for in_shop and manager roles
#
# Drivers do NOT subscribe to shop_full; in_shop/manager do NOT subscribe to
# driver. Reference is shared by all.

bucket_definitions:

  reference:
    # Every authenticated user sees the lookup tables.
    parameters: SELECT request.user_id() AS user_id
    data:
      - SELECT * FROM valid_transitions
      - SELECT id, username, display_name, role, active FROM staff
      - SELECT * FROM customers WHERE deleted_at IS NULL

  driver:
    # Personal bucket for each driver: orders they're assigned to, the events
    # and proofs that hang off those orders, and their own shifts. Other
    # drivers' data does not leak in.
    parameters: |
      SELECT request.user_id() AS user_id
      WHERE request.jwt() ->> 'role' = 'driver'
    data:
      - SELECT * FROM orders
          WHERE (assigned_driver = bucket.user_id::uuid
                 OR assigned_driver IS NULL)
            AND deleted_at IS NULL
      - SELECT ose.* FROM order_status_events ose
          JOIN orders o ON o.id = ose.order_id
          WHERE (o.assigned_driver = bucket.user_id::uuid
                 OR o.assigned_driver IS NULL)
            AND o.deleted_at IS NULL
      - SELECT pe.* FROM proof_events pe
          JOIN orders o ON o.id = pe.order_id
          WHERE (o.assigned_driver = bucket.user_id::uuid
                 OR o.assigned_driver IS NULL)
            AND o.deleted_at IS NULL
            AND pe.deleted_at IS NULL
      - SELECT pp.* FROM proof_photos pp
          JOIN proof_events pe ON pe.id = pp.proof_event_id
          JOIN orders       o  ON o.id  = pe.order_id
          WHERE (o.assigned_driver = bucket.user_id::uuid
                 OR o.assigned_driver IS NULL)
            AND o.deleted_at IS NULL
            AND pe.deleted_at IS NULL
      - SELECT * FROM issues   WHERE reported_by = bucket.user_id::uuid
      - SELECT * FROM shifts   WHERE staff_id   = bucket.user_id::uuid

  shop_full:
    # in_shop and manager roles get the whole operational dataset.
    parameters: |
      SELECT request.user_id() AS user_id
      WHERE request.jwt() ->> 'role' IN ('in_shop', 'manager')
    data:
      - SELECT * FROM orders               WHERE deleted_at IS NULL
      - SELECT * FROM order_status_events
      - SELECT * FROM proof_events         WHERE deleted_at IS NULL
      - SELECT * FROM proof_photos
      - SELECT * FROM issues
      - SELECT * FROM shifts
```

- [ ] **Step 3: Validate the YAML locally (syntactic only)**

PowerSync's full semantic validation happens when you upload to the service. For syntactic checks before upload:

```powershell
# Verify the file is well-formed YAML
python -c "import yaml,sys; yaml.safe_load(open('powersync/sync-rules.yaml')); print('OK')"
```

Expected: `OK`. If Python is not available, open the file in VS Code with the YAML extension and confirm no red squiggles.

- [ ] **Step 4: Commit**

```powershell
git add powersync/sync-rules.yaml
git commit -m "Add PowerSync sync rules: reference + driver + shop_full buckets"
```

---

## Task 3: PowerSync account + instance (manual, documented)

This task is manual clickops in the PowerSync dashboard plus one manual SQL in the Supabase SQL editor. The objective is a running PowerSync instance connected to the Amuwak Supabase project with the sync rules from Task 2 deployed.

**Files:**
- Create: `powersync/README.md`

- [ ] **Step 1: Set the powersync role's password (Supabase SQL editor)**

Open `https://supabase.com/dashboard/project/rrxcsscinwqrxivczrfg/sql/new` and run:

```sql
-- Replace the placeholder with a strong, randomly generated password.
-- Generate one in PowerShell:  -join ((48..57)+(65..90)+(97..122)+(33,35,36,37,38,42,43) | Get-Random -Count 40 | % {[char]$_})
ALTER ROLE powersync WITH LOGIN PASSWORD '<GENERATED_PASSWORD>';
```

Expected: `ALTER ROLE`. **Copy the password to your password manager immediately.** It will not be printed back to you again.

- [ ] **Step 2: Sign up for PowerSync and create the instance**

1. Go to `https://accounts.journeyapps.com/portal/free-trial`. Sign up (free tier).
2. From the PowerSync dashboard, **Create new instance** → name: `amuwak-staff-dev` → region: closest to eu-west-2 (typically eu-west-1).

- [ ] **Step 3: Connect the instance to Supabase Postgres**

Inside the PowerSync instance settings → **Database connections** → **Add connection** → **Postgres**.

Fill in:
- **Host:** `aws-1-eu-west-2.pooler.supabase.com`
- **Port:** `5432`
- **Database:** `postgres`
- **Username:** `powersync.rrxcsscinwqrxivczrfg` (PowerSync needs the role name with the project ref appended for the pooler)
- **Password:** the password you set in Step 1.
- **Publication:** `powersync`
- **Slot name:** `powersync` (PowerSync creates the slot if it doesn't exist)
- **TLS / SSL:** required.

Save. The connection status should turn green within ~30 seconds.

- [ ] **Step 4: Configure JWKS-based JWT auth**

In the PowerSync instance settings → **Auth** → **Add JWKS URI**:

- **JWKS URI:** `https://rrxcsscinwqrxivczrfg.supabase.co/auth/v1/.well-known/jwks.json`
- **Audience:** `authenticated`
- **Issuer:** `https://rrxcsscinwqrxivczrfg.supabase.co/auth/v1`

Save.

- [ ] **Step 5: Upload sync rules**

PowerSync instance → **Sync rules** → paste the contents of `powersync/sync-rules.yaml` → **Validate** (the dashboard reports any semantic errors) → **Deploy**.

Expected: validator reports zero errors; the dashboard shows the three buckets (`reference`, `driver`, `shop_full`).

- [ ] **Step 6: Smoke-check the replication stream**

PowerSync instance → **Diagnostics** → **Replication health**. Expected: `connected`, with a recent `last_replication_lsn` advancing as you make changes in Supabase Studio.

To force a visible change, run in the Supabase SQL editor:

```sql
INSERT INTO public.customers (name, phone, address)
VALUES ('PowerSync Smoke Test', '+254700000000', 'Test Address');
```

Within a couple of seconds, the PowerSync **Diagnostics** view should show the WAL position advancing past this insert.

- [ ] **Step 7: Capture the PowerSync endpoint URL**

PowerSync instance settings → **Endpoint**. The URL looks like `https://<instance-id>.powersync.journeyapps.com`. Copy it to your password manager — the Flutter app (Plan 3) will read it from `--dart-define=POWERSYNC_URL=…`.

- [ ] **Step 8: Write the powersync README**

Create `powersync/README.md`:

```markdown
# PowerSync setup — Amuwak Staff

PowerSync provides bidirectional offline sync between the Supabase Postgres
project (`rrxcsscinwqrxivczrfg`) and the Flutter app. The instance is
operated through the PowerSync cloud dashboard; this directory holds the
declarative artifacts (sync rules) that are version-controlled.

## Layout

| File                  | Purpose                                                          |
|-----------------------|------------------------------------------------------------------|
| `sync-rules.yaml`     | Bucket definitions deployed to the PowerSync instance.           |
| `README.md`           | This file — setup and operational runbook.                       |

## One-time setup

1. Apply Supabase migration `0015_powersync_replication.sql` (see `../supabase/`).
2. In the Supabase SQL editor, set a password on the `powersync` role:
   ```sql
   ALTER ROLE powersync WITH LOGIN PASSWORD '<GENERATED_PASSWORD>';
   ```
   Store the password in a password manager.
3. Sign up for PowerSync at https://accounts.journeyapps.com/portal/free-trial.
4. Create an instance (`amuwak-staff-dev`, region eu-west-1).
5. Connect to Supabase: host `aws-1-eu-west-2.pooler.supabase.com`, port `5432`,
   user `powersync.rrxcsscinwqrxivczrfg`, password from step 2, publication
   `powersync`, slot `powersync`.
6. Add JWKS auth pointing at
   `https://rrxcsscinwqrxivczrfg.supabase.co/auth/v1/.well-known/jwks.json`,
   audience `authenticated`, issuer
   `https://rrxcsscinwqrxivczrfg.supabase.co/auth/v1`.
7. Upload `sync-rules.yaml` to the instance → validate → deploy.
8. Capture the instance endpoint URL for the Flutter app (Plan 3).

## Updating sync rules

1. Edit `sync-rules.yaml`. Commit.
2. PowerSync dashboard → Sync rules → paste the new content → validate → deploy.
3. The instance redeploys; existing clients reconnect and replay the relevant
   buckets.

Sync rules are NOT auto-deployed from this repo — the dashboard is the source
of truth at runtime. Keep them in sync by reviewing diffs as part of code
review.

## Buckets

| Bucket       | Membership                                     | Contents                                                                 |
|--------------|------------------------------------------------|--------------------------------------------------------------------------|
| `reference`  | Every signed-in staff member                   | `valid_transitions`, `staff` list (minus PINs), `customers`              |
| `driver`     | `role='driver'`, scoped to `request.user_id()` | Their orders (assigned or unassigned), descendants, their own issues + shifts |
| `shop_full`  | `role='in_shop'` or `role='manager'`           | All non-deleted orders, all events, all proofs, all issues, all shifts   |

## Operational notes

- The `powersync` Postgres role has `BYPASSRLS`. Sync rules do all per-user
  filtering — RLS does not apply to the replication stream.
- Free tier limit: one instance, ~10 concurrent clients. Plenty for pilot.
- If the replication slot lags (instance disconnected for a long stretch),
  Postgres WAL grows. Reconnect or recreate the slot if disk usage climbs.

## Reference docs

- PowerSync Supabase integration:
  https://docs.powersync.com/integration-guides/supabase
- Spec: [../docs/superpowers/specs/2026-05-18-supabase-backend-design.md](../docs/superpowers/specs/2026-05-18-supabase-backend-design.md)
```

- [ ] **Step 9: Commit**

```powershell
git add powersync/README.md
git commit -m "Document PowerSync instance setup and runbook"
```

---

## Task 4: End-to-end smoke check

This task verifies that the chain Supabase → publication → PowerSync → bucket actually works by inspecting the PowerSync instance's `Diagnostics` view after a Postgres write.

**Files:** (none — verification only)

- [ ] **Step 1: Insert a test row in Supabase**

In the Supabase SQL editor:

```sql
INSERT INTO public.customers (name, phone, address)
VALUES ('E2E Smoke', '+254700001111', 'Smoke Test Address');
```

- [ ] **Step 2: Confirm PowerSync saw it**

PowerSync dashboard → instance → **Diagnostics** → **Replication health**.

Expected: the `last_replication_lsn` field increments. In the **Event log**, you should see an insert event referencing the `customers` table within ~5 seconds.

If the LSN doesn't move:

- Recheck the publication includes `customers`:
  ```sql
  SELECT * FROM pg_publication_tables WHERE pubname = 'powersync';
  ```
- Recheck the `powersync` role has LOGIN and the password matches the dashboard.
- Recheck the replication slot exists in Postgres:
  ```sql
  SELECT slot_name, active, restart_lsn FROM pg_replication_slots;
  ```

- [ ] **Step 3: Clean up the test row**

```sql
DELETE FROM public.customers WHERE name IN ('PowerSync Smoke Test', 'E2E Smoke');
```

PowerSync should record the delete in its event log too.

- [ ] **Step 4: Final commit (workspace clean)**

```powershell
git status --short
```

Expected: only the pre-existing unrelated Flutter platform files remain
unstaged. Nothing left to commit for Plan 2.

---

## Self-review checklist (for the implementer)

After all tasks are merged, verify:

- [ ] `supabase test db` (or `psql -f supabase/tests/0015_…`) reports 8/8 passing.
- [ ] PowerSync **Diagnostics** shows `connected` and an advancing LSN.
- [ ] Sync rules dashboard shows three buckets: `reference`, `driver`, `shop_full`.
- [ ] `powersync` Postgres role exists, has LOGIN, REPLICATION, BYPASSRLS.
- [ ] `powersync/README.md` documents how to rotate the role's password.
- [ ] No production secret (`powersync` role password, PowerSync instance URL token) is committed to the repo.

## What this plan does not do

- **Client integration.** The Flutter app does not yet subscribe to PowerSync.
  That's Plan 3 (`supabase_flutter` + `powersync_flutter` wiring) — it consumes
  the instance URL captured in Task 3, Step 7.
- **Photo uploads.** The `proof_photos` rows sync, but the photo binaries are
  in Supabase Storage and don't flow through PowerSync. The local upload
  outbox is Plan 4.
- **Schema drift detection.** If someone changes a Postgres column that the
  sync rules reference (e.g. adds a NOT NULL column without a default to
  `orders`), PowerSync will continue replicating but the new column won't
  appear in client schemas until you redeploy the sync rules. Plan 3 covers
  the client-side schema declaration that pairs with this.
