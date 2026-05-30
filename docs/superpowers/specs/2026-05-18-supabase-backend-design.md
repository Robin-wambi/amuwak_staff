# Supabase Backend Design — 2026-05-18

**Status:** Design approved, pending implementation plan.
**Scope:** Backend datastore, sync, auth, and storage for **Amuwak Staff** — the Flutter staff-facing app for door-to-door laundry operations in Africa (Kenya/Nigeria pilot).

## Context

The app today holds all order data in memory. To support multiple devices (drivers in the field + in-shop counter staff + a manager), photo proof of pickup/delivery, audit-grade status history, and the connectivity realities of the target markets, we need a real backend. The research doc `2026-05-12-laundry-staff-feature-research.md` identifies offline-first sync (A3) as a non-negotiable: "the app should never lose a status update."

## Goals

- Persist orders, status transitions, proof events, and proof photos across devices.
- Work fully offline — drivers can create orders, capture proofs, and scan QR transitions with no signal; everything syncs on reconnect.
- Enforce role-based access at the database level (drivers see their assignments; in-shop staff see the floor; managers see everything).
- Keep operational cost at zero during the pilot (free tiers only) with a clear migration path to paid plans.
- Match patterns used by the existing Dart code (`LaundryOrder`, `OrderStatus`, `ProofEvent`) so the migration is incremental.

## Non-goals

- Customer-facing app or portal (separate project).
- Multi-tenant SaaS (single business; multi-tenancy can be retrofitted later).
- Payment processing (out of scope; status field `paid` boolean only).
- Real-time chat / messaging (WhatsApp deep links handled client-side).

## Decisions summary

| Area              | Decision                                                        |
|-------------------|-----------------------------------------------------------------|
| Backend platform  | **Supabase** (Postgres + Auth + Storage + Realtime)             |
| Offline sync      | **PowerSync** (bidirectional sync, local SQLite, Flutter SDK)   |
| Tenancy           | **Single business** (no `tenant_id`)                            |
| Auth model        | **Username + PIN via email-trick** on Supabase Auth             |
| Photo storage     | Supabase Storage + local outbox queue                           |
| Hosting region    | **eu-west-2 (London)** — closest Supabase region to East/West Africa |
| Cost tier         | **Free tier** for Supabase and PowerSync during pilot           |

## Architecture

```
┌─────────────────────────┐        ┌──────────────────────────┐
│  Flutter app (staff)    │        │   Supabase (cloud)       │
│                         │        │                          │
│  ┌───────────────────┐  │        │  ┌────────────────────┐  │
│  │ PowerSync SDK     │◄─┼────────┼─►│ PowerSync Service  │  │
│  │ + local SQLite    │  │ sync   │  │ (replicates from   │  │
│  └───────────────────┘  │ stream │  │  Postgres WAL)     │  │
│         ▲               │        │  └─────────┬──────────┘  │
│         │               │        │            │             │
│  ┌───────────────────┐  │        │  ┌─────────▼──────────┐  │
│  │ App UI + repos    │  │        │  │ Postgres (orders,  │  │
│  └─────────┬─────────┘  │        │  │ staff, proof…)     │  │
│            │            │        │  │ + RLS policies     │  │
│  ┌─────────▼─────────┐  │ direct │  └────────────────────┘  │
│  │ Photo upload queue│──┼────────┼─►┌────────────────────┐  │
│  │ (SQLite outbox)   │  │ HTTPS  │  │ Supabase Storage   │  │
│  └───────────────────┘  │        │  │ (proof-photos)     │  │
│                         │        │  └────────────────────┘  │
│  ┌───────────────────┐  │        │  ┌────────────────────┐  │
│  │ supabase_flutter  │◄─┼────────┼─►│ Supabase Auth      │  │
│  │ (auth + storage)  │  │        │  │ (JWT, email-trick) │  │
│  └───────────────────┘  │        │  └────────────────────┘  │
└─────────────────────────┘        └──────────────────────────┘
```

Three concerns are kept separate:

1. **Structured data** — orders, statuses, staff, proof events — flows through PowerSync. Every write is local-first.
2. **Photos** — PowerSync does not sync blobs. We store a path reference in the synced `proof_photos` row and let a separate local upload queue drain the actual bytes to Supabase Storage.
3. **Auth** — `supabase_flutter` handles sign-in once at the start of a shift; the JWT is then handed to PowerSync for sync authorization.

## Database schema

All primary keys are UUIDs (so offline clients can mint IDs without coordination). Every table has `created_at`, `updated_at`, and where appropriate `deleted_at` (soft delete — PowerSync propagates deletes as updates).

```sql
-- Identity & roles
CREATE TABLE staff (
  id              uuid PRIMARY KEY,                 -- == auth.users.id
  username        text UNIQUE NOT NULL,             -- e.g. 'john'
  display_name    text NOT NULL,
  phone           text,
  role            text NOT NULL CHECK (role IN ('driver','in_shop','manager')),
  active          boolean NOT NULL DEFAULT true,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz
);

-- Customers
CREATE TABLE customers (
  id              uuid PRIMARY KEY,
  name            text NOT NULL,
  phone           text NOT NULL,
  address         text,
  notes           text,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz
);

-- Orders
CREATE TABLE orders (
  id                  uuid PRIMARY KEY,
  order_code          text UNIQUE NOT NULL,         -- human-readable, e.g. 'AMW-00421'
  customer_id         uuid REFERENCES customers(id),
  customer_name       text NOT NULL,                -- denormalized snapshot
  phone               text NOT NULL,
  address             text NOT NULL,
  service_type        text NOT NULL,                -- 'wash_fold' | 'dry_clean' | ...
  status              text NOT NULL,                -- denormalized cache of latest event
  intake_method       text NOT NULL
    CHECK (intake_method IN ('driver_pickup','walk_in','phone_order')),
  fulfillment_method  text NOT NULL
    CHECK (fulfillment_method IN ('delivery','customer_collect')),
  item_count          int NOT NULL,
  notes               text NOT NULL DEFAULT '',
  scheduled_for       timestamptz,
  assigned_driver     uuid REFERENCES staff(id),    -- nullable
  intake_recorded_by  uuid NOT NULL REFERENCES staff(id),
  created_by          uuid NOT NULL REFERENCES staff(id),
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  deleted_at          timestamptz
);
CREATE INDEX ON orders (status) WHERE deleted_at IS NULL;
CREATE INDEX ON orders (assigned_driver) WHERE deleted_at IS NULL;

-- Append-only status transition log (audit trail)
CREATE TABLE order_status_events (
  id              uuid PRIMARY KEY,
  order_id        uuid NOT NULL REFERENCES orders(id),
  from_status     text,
  to_status       text NOT NULL,
  changed_by      uuid NOT NULL REFERENCES staff(id),
  changed_at      timestamptz NOT NULL DEFAULT now(),
  source          text NOT NULL,                    -- 'qr_scan' | 'manual' | 'system'
  device_event_id text UNIQUE                       -- client-generated idempotency key
);

-- Pickup / delivery proof events
CREATE TABLE proof_events (
  id              uuid PRIMARY KEY,
  order_id        uuid NOT NULL REFERENCES orders(id),
  type            text NOT NULL CHECK (type IN ('pickup','delivery')),
  captured_at     timestamptz NOT NULL,
  item_count      int NOT NULL,
  notes           text,
  captured_by     uuid NOT NULL REFERENCES staff(id),
  created_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz
);
CREATE UNIQUE INDEX proof_events_one_per_type
  ON proof_events (order_id, type) WHERE deleted_at IS NULL;

-- Photos attached to proof events
CREATE TABLE proof_photos (
  id              uuid PRIMARY KEY,
  proof_event_id  uuid NOT NULL REFERENCES proof_events(id) ON DELETE CASCADE,
  storage_path    text NOT NULL,                    -- 'proof/2026/05/<order>/<event>/<photo>.jpg'
  width           int,
  height          int,
  bytes           int,
  uploaded_at     timestamptz,                      -- null until upload completes
  created_at      timestamptz NOT NULL DEFAULT now()
);

-- Issues / incidents
CREATE TABLE issues (
  id              uuid PRIMARY KEY,
  order_id        uuid REFERENCES orders(id),
  kind            text NOT NULL CHECK (kind IN ('damage','missing','complaint','other')),
  description     text NOT NULL,
  reported_by     uuid NOT NULL REFERENCES staff(id),
  reported_at     timestamptz NOT NULL DEFAULT now(),
  resolved_at     timestamptz,
  resolved_by     uuid REFERENCES staff(id)
);

-- Shift check-in/out
CREATE TABLE shifts (
  id              uuid PRIMARY KEY,
  staff_id        uuid NOT NULL REFERENCES staff(id),
  started_at      timestamptz NOT NULL,
  started_lat     numeric,
  started_lng     numeric,
  ended_at        timestamptz,
  ended_lat       numeric,
  ended_lng       numeric
);
```

### Status state machine

The status enum widens to handle walk-ins and counter-collection:

| Status            | When applied                                                 |
|-------------------|--------------------------------------------------------------|
| `pending_pickup`  | Driver hasn't collected yet (`driver_pickup` / `phone_order`)|
| `received`        | Items physically in the shop                                 |
| `in_progress`     | Being washed / ironed                                        |
| `ready`           | Done, awaiting handoff (delivery *or* counter collect)       |
| `out_for_delivery`| Driver en route to customer (delivery only)                  |
| `completed`       | Handed off                                                   |

Valid transitions depend on `(intake_method, fulfillment_method)`:

```
walk_in       + customer_collect:  received → in_progress → ready → completed
walk_in       + delivery:          received → in_progress → ready → out_for_delivery → completed
driver_pickup + customer_collect:  pending_pickup → received → in_progress → ready → completed
driver_pickup + delivery:          pending_pickup → received → in_progress → ready → out_for_delivery → completed
phone_order   + *:                 same as driver_pickup variants
```

A `BEFORE INSERT` trigger on `order_status_events` validates that the proposed transition is legal for the order's `(intake_method, fulfillment_method)` against a small `valid_transitions` lookup table:

```sql
CREATE TABLE valid_transitions (
  intake_method       text NOT NULL,
  fulfillment_method  text NOT NULL,
  from_status         text,                          -- NULL = initial state allowed
  to_status           text NOT NULL,
  PRIMARY KEY (intake_method, fulfillment_method, from_status, to_status)
);
-- Seeded once with the matrix above. Insert-only; managed via migrations.
```

### Schema-side guardrails

- **Idempotency:** `device_event_id UNIQUE` on `order_status_events` — replaying a queued status change after reconnect is a no-op.
- **Audit trail is immutable:** no `UPDATE` or `DELETE` RLS policies on `order_status_events`.
- **Denormalized customer snapshot** on `orders.customer_name/phone/address` protects historical records from later customer-record edits.
- **Soft delete only**: `deleted_at` lets PowerSync propagate removals as updates.
- `updated_at` is maintained by a `BEFORE UPDATE` trigger on every table that has it.
- FKs that PowerSync writes during sync are `DEFERRABLE INITIALLY DEFERRED` so out-of-order inserts inside a sync batch don't violate constraints.

## Row-Level Security

A helper function avoids recursive policy evaluation on `staff`:

```sql
CREATE FUNCTION auth_staff_role() RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER AS $$
  SELECT role FROM staff WHERE id = auth.uid() AND active = true
$$;
```

Key policies (full file in `supabase/migrations/`):

```sql
-- staff: own row + manager all-access
CREATE POLICY staff_self_read ON staff FOR SELECT
  USING (id = auth.uid() OR auth_staff_role() = 'manager');
CREATE POLICY staff_manager_write ON staff FOR ALL
  USING (auth_staff_role() = 'manager')
  WITH CHECK (auth_staff_role() = 'manager');

-- orders: driver sees own + unassigned; in_shop / manager see all
CREATE POLICY orders_read ON orders FOR SELECT USING (
  CASE auth_staff_role()
    WHEN 'driver'  THEN assigned_driver = auth.uid() OR assigned_driver IS NULL
    WHEN 'in_shop' THEN true
    WHEN 'manager' THEN true
    ELSE false
  END
);

-- orders: who can create which intake type
CREATE POLICY orders_insert ON orders FOR INSERT WITH CHECK (
  CASE auth_staff_role()
    WHEN 'driver'  THEN
      intake_method = 'driver_pickup'
      AND assigned_driver = auth.uid()
      AND intake_recorded_by = auth.uid()
    WHEN 'in_shop' THEN true
    WHEN 'manager' THEN true
    ELSE false
  END
);

CREATE POLICY orders_update ON orders FOR UPDATE USING (
  auth_staff_role() IN ('in_shop','manager')
  OR (auth_staff_role() = 'driver' AND assigned_driver = auth.uid())
);

-- order_status_events: append-only
CREATE POLICY status_events_insert ON order_status_events FOR INSERT
  WITH CHECK (changed_by = auth.uid());
CREATE POLICY status_events_read ON order_status_events FOR SELECT
  USING (EXISTS (SELECT 1 FROM orders o WHERE o.id = order_id));
-- (no UPDATE / DELETE policies → denied)

-- proof_events / proof_photos: piggyback off orders visibility
CREATE POLICY proof_events_read ON proof_events FOR SELECT USING (
  EXISTS (SELECT 1 FROM orders o WHERE o.id = order_id)
);
CREATE POLICY proof_events_write ON proof_events FOR INSERT
  WITH CHECK (captured_by = auth.uid());
```

Principles:
- **`SECURITY DEFINER` helper** prevents recursive RLS on `staff`.
- **`WITH CHECK` clauses** stop forged attribution (a client can't claim someone else captured a proof).
- **No service-role key on the client** — the app only ever uses the user's JWT.
- **Walk-in/phone-order ownership:** in-shop staff own those intake paths; drivers can only create `driver_pickup` orders assigned to themselves.

## PowerSync sync rules

Sync rules mirror RLS so a driver's local SQLite literally cannot contain other drivers' orders. The staff role is injected into the JWT via an auth hook (see Auth section) so sync rules can read it.

```yaml
bucket_definitions:
  staff_self:
    parameters: SELECT request.user_id() AS user_id
    data:
      - SELECT * FROM staff WHERE id = bucket.user_id

  driver_orders:
    parameters: |
      SELECT request.user_id() AS driver_id
      WHERE request.jwt() ->> 'role' = 'driver'
    data:
      - SELECT * FROM orders
          WHERE (assigned_driver = bucket.driver_id OR assigned_driver IS NULL)
            AND deleted_at IS NULL
      - SELECT * FROM order_status_events
          WHERE order_id IN (
            SELECT id FROM orders
            WHERE assigned_driver = bucket.driver_id OR assigned_driver IS NULL
          )
      - SELECT * FROM proof_events  WHERE order_id IN (...same subquery...)
      - SELECT * FROM proof_photos  WHERE proof_event_id IN (
          SELECT id FROM proof_events WHERE order_id IN (...)
        )
      - SELECT * FROM issues        WHERE order_id IN (...)

  shop_orders:
    parameters: |
      SELECT 1 WHERE request.jwt() ->> 'role' IN ('in_shop','manager')
    data:
      - SELECT * FROM orders               WHERE deleted_at IS NULL
      - SELECT * FROM order_status_events
      - SELECT * FROM proof_events         WHERE deleted_at IS NULL
      - SELECT * FROM proof_photos
      - SELECT * FROM issues
      - SELECT * FROM customers            WHERE deleted_at IS NULL

  staff_directory:
    parameters: SELECT 1
    data:
      - SELECT id, display_name, role, active FROM staff
          WHERE active = true AND deleted_at IS NULL

  shifts_manager:
    parameters: |
      SELECT 1 WHERE request.jwt() ->> 'role' = 'manager'
    data:
      - SELECT * FROM shifts
```

Principles:
- Sync rules are a **subset** of RLS — never more permissive.
- Bucket-per-driver scales naturally: reassigning an order causes it to disappear from driver A's local DB and appear in driver B's, with no app code involved.
- Photo bytes are never synced; only `proof_photos` metadata rows.

## Photo storage strategy

A dedicated Supabase Storage bucket, date-partitioned for listability and lifecycle rules.

```
Bucket: proof-photos     (private)
Path:   proof/<YYYY>/<MM>/<order_code>/<proof_event_id>/<photo_uuid>.jpg
```

### Capture & upload flow

1. Driver taps "Capture pickup proof" — UI opens the camera.
2. App writes `proof_event` + N `proof_photo` rows to local SQLite. PowerSync will sync them on reconnect.
3. Each photo is compressed (`flutter_image_compress`, already in `pubspec.yaml`) to ~80% JPEG, max 1600px on longest side, EXIF GPS stripped.
4. Compressed bytes go to app-private file storage at `<path_provider>/proof_queue/<photo_uuid>.jpg`.
5. An entry is inserted in a **local-only** SQLite table `upload_queue` (declared as local-only in PowerSync — it does not sync):

```
upload_queue (photo_uuid, storage_path, local_file_path, attempts, last_error, next_retry_at)
```

6. A background worker (`WorkManager` Android / `BGTaskScheduler` iOS, plus a foreground tick) drains the queue:

```dart
while (await upload_queue.hasPending()) {
  final item = await upload_queue.next();
  try {
    await supabase.storage.from('proof-photos').upload(
      item.storagePath,
      File(item.localFilePath),
      fileOptions: FileOptions(contentType: 'image/jpeg', upsert: false),
    );
    await proof_photos.update(item.photoUuid, uploaded_at: DateTime.now());
    await upload_queue.remove(item);
    await deleteLocalFile(item.localFilePath);
  } catch (e) {
    await upload_queue.markFailed(item, error: e, nextRetryAt: backoff(item.attempts));
  }
}
```

Practices baked in:
- **Idempotent uploads:** UUID-based path + `upsert: false`; a 409 on retry is treated as success.
- **Exponential backoff with jitter** — protects Storage from a thundering herd when many phones reconnect at shift start.
- **Two-phase visibility:** the `proof_photos` row syncs first; managers see "proof exists, photo uploading" via `uploaded_at IS NULL`.
- **Compress before queueing**, not just before uploading — a phone might queue dozens of photos before reaching wifi.
- **EXIF GPS stripped** before upload — customer-home coordinates are a privacy hazard.
- **Signed URLs** for viewing (`createSignedUrl(path, expiresIn: 3600)`), not a public bucket.
- **Photos are immutable.** Even managers cannot delete via the app — only via a server-side admin tool with audit logging.

Storage RLS:

```sql
CREATE POLICY proof_photos_read ON storage.objects FOR SELECT
  USING (bucket_id = 'proof-photos' AND auth.role() = 'authenticated');

CREATE POLICY proof_photos_write ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'proof-photos'
    AND auth.role() = 'authenticated'
    AND (storage.foldername(name))[1] = 'proof'
  );
-- No UPDATE or DELETE policies → photos are immutable
```

## Auth flow

Username + PIN, layered on Supabase Auth via the email-trick:

```
email    = '${username.toLowerCase()}@amuwak.local'
password = pin
supabase.auth.signInWithPassword(email, password)
→ JWT with sub = staff.id, custom claim 'role' from auth hook
→ JWT passed to PowerSync client → sync begins
```

### Custom claim hook

So sync rules can read `role` from the JWT:

```sql
CREATE FUNCTION public.custom_access_token_hook(event jsonb)
RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
  claims jsonb;
  staff_role text;
BEGIN
  SELECT role INTO staff_role FROM public.staff
    WHERE id = (event->>'user_id')::uuid AND active = true;
  claims := event->'claims';
  claims := jsonb_set(claims, '{role}', to_jsonb(coalesce(staff_role, 'none')));
  RETURN jsonb_set(event, '{claims}', claims);
END;
$$;
-- Wired up via Supabase Dashboard → Auth → Hooks
```

### Manager-only "create staff" via Edge Function

```typescript
// supabase/functions/create-staff/index.ts
serve(async (req) => {
  const caller = await getUser(req);
  if (caller.role !== 'manager') return forbidden();

  const { username, displayName, role, initialPin } = await req.json();
  const email = `${username.toLowerCase()}@amuwak.local`;

  const { data: user } = await admin.auth.admin.createUser({
    email, password: initialPin, email_confirm: true,
  });
  await admin.from('staff').insert({
    id: user.id, username, display_name: displayName, role,
  });

  return ok({ id: user.id });
});
```

### PIN changes & lockouts

- **Self change:** old PIN + new PIN via `supabase.auth.updateUser({ password: newPin })`.
- **Manager reset:** Edge Function calls `admin.auth.admin.updateUserById(id, { password: tempPin })`; flags `must_change_pin` on the `staff` row.
- **PIN policy** enforced in the function: 4–8 digits, not the username, not in a blocklist (`0000`, `1234`, `1111`, etc.).
- **Lockouts:** an `auth_attempts` table + Edge Function wrapper around sign-in; 5 failures within 15 minutes locks the username for 30 minutes. Wired in a later iteration.

## Operational practices

### Region

**eu-west-2 (London).** Supabase has no Africa region. London gives the lowest median RTT (~150–220ms) to Kenya/Nigeria in observed tests, ahead of us-east-1 and ap-south-1. Region cannot be changed after project creation.

### Environments

Three Supabase projects: `amuwak-dev`, `amuwak-staging`, `amuwak-prod`. The Flutter app picks one via `--dart-define=SUPABASE_URL=...` at build time. Never share a database between staging and prod.

### Migrations

`supabase migration new` / `supabase db push`. Every migration committed to `supabase/migrations/` in git. PowerSync sync rules also live in version control and are deployed alongside.

### Backups

- Supabase free tier: daily logical backups, **no point-in-time recovery**.
- Mitigation during pilot: a weekly `pg_dump` to S3-compatible storage (Backblaze B2 free tier — 10 GB) via a GitHub Action.
- Plan to upgrade to Supabase Pro (PITR with 7-day window) before production scale.

### Observability

- **Supabase Logs** — built-in.
- **Sentry** in Flutter for crash + error reports (free dev plan).
- **PowerSync dashboard** for sync lag and replication errors.
- **Synthetic health check:** a cron Edge Function pings a `health` table every 5 minutes.

### Connection management

- PowerSync uses a long-lived websocket.
- Direct `supabase_flutter` calls (photo upload, auth, Edge Functions) use HTTPS via the connection pooler.
- App never opens a raw Postgres connection — always PostgREST.

### Secrets

- `SUPABASE_URL` and the **anon key** ship in the app — public, by design.
- The **service role key** lives only in Edge Functions and CI secrets. Rotated quarterly and after any device loss.

### Free-tier constraints & risk register

| Limit                                  | Free-tier value         | Risk for this app                                            | Mitigation                                                  |
|----------------------------------------|-------------------------|--------------------------------------------------------------|-------------------------------------------------------------|
| Supabase DB size                       | 500 MB                  | Tiny — orders/rows are small; unlikely to breach in pilot    | Monitor monthly                                             |
| Supabase Storage                       | 1 GB                    | ~50 orders/day × 4 photos × 200KB ≈ 8 MB/day → fills in ~4 months | Lifecycle policy: archive >90-day photos to Backblaze       |
| Supabase egress                        | 2 GB / month            | Manager photo browsing could spike egress                     | Thumbnail variant generated on upload; full-res lazy-loaded |
| Supabase MAU                           | 50K                     | Staff app — well under                                        | N/A                                                         |
| Project pause after 1 week inactivity  | Yes (free tier only)    | A long pilot gap could pause the project                      | Synthetic health check ping keeps it active                 |
| PowerSync synced data                  | 3 GB                    | Photos don't sync via PowerSync; row data is small            | Monitor; upgrade if approached                              |
| PowerSync concurrent connections       | 10                      | One shop with <10 active devices — fits                       | Track in dashboard; upgrade for multi-shop                  |
| No PITR backups on Supabase free       | —                       | Cannot recover from a "bad UPDATE wiped data 4 hours ago" mistake | Weekly `pg_dump` to Backblaze; upgrade to Pro before scale  |

## Open questions / future work

- **QR code format & scope:** does each order get a unique printed QR, or is there a scheme that encodes the order_code? (Pickup/delivery proof spec already exists at [pickup-delivery-proof-design.md](2026-05-12-pickup-delivery-proof-design.md) — cross-reference during implementation.)
- **Push notifications:** Supabase has no native push. Likely OneSignal free tier or Firebase Cloud Messaging. Out of scope for this spec.
- **WhatsApp templates (research B1):** triggered server-side from a `whatsapp_outbox` table? Or client-side deep links only? Decide in a follow-up spec.
- **End-of-day driver summary (research B4):** can be a Postgres view; no schema change needed.
- **Payment status:** the `orders` table does not yet model `paid` / `amount_owed`. Add when payment flows are designed.
- **Reporting / analytics:** a daily-refresh materialized view layer or a read-replica? Defer until volume warrants.

## Glossary

- **PowerSync** — third-party bidirectional sync engine that replicates Postgres tables to local SQLite on each client.
- **Sync rules** — YAML declaration that defines, per JWT, which rows a client downloads.
- **RLS** — Postgres Row-Level Security, enforced server-side on every query.
- **Email-trick** — pattern of synthesizing internal-only email addresses (e.g. `john@amuwak.local`) to use Supabase Auth's email/password flow with username/PIN UX.
- **Outbox** — local-only table that queues operations (here, photo uploads) for later transmission.
