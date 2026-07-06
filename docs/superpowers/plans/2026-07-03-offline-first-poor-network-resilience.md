# Poor-Network Resilience: Re-enable Offline-First for Orders

## Context

Riders in the field hit "poor network" errors and **cannot save an order at all**. Today the app runs
in **online-only mode**: every order write (`create_pickup` RPC, status/detail/pricing updates, proof
events) goes *straight* to Supabase with **no retry, no timeout tuning, and no local buffering**. A
flaky or absent connection throws immediately, and the rider is left tapping "retry" against a dead
network. This is the core workflow of a field tool, so it must survive both **flaky-but-present** and
**fully-offline** conditions.

**Key finding:** the app already contains a complete, production-grade **offline-first sync engine**
(Drift/SQLite local store + durable **outbox** queue with dedup/retry/dead-lettering + background
worker + puller + connectivity watcher + `SyncStatusBanner`/`SyncErrorsScreen` UI). It was
deliberately **disabled** during the online-only migration (commented out, not deleted). This plan
**re-enables it**, so orders save to local disk instantly and sync in the background. We are not
building from scratch — we are rewiring what exists and solving two gaps the old code doesn't cover.

**Intended outcome:** tap "Create pickup" with zero bars → order appears on the dashboard instantly
as "pending sync" → when signal returns (even briefly/flaky) the outbox drains automatically, the real
`AMW-…` order code backfills, and pending count drops to 0. Nothing is lost on app restart.

## The two hard problems (and their solutions)

### Problem 1 — `create_pickup` is now an RPC, not a plain table insert
Order creation goes through `create_pickup(p_customer, p_order)` — a `SECURITY DEFINER` RPC
(`supabase/migrations/0040_create_pickup_rpc.sql`) that mints `order_code` server-side, sets
`assigned_driver` by role, and **exists specifically to bypass the rider RLS** that blocks direct
`customers`/`orders` inserts. The old outbox dispatches plain `client.from(table).insert()` — which a
rider **cannot** do. Solution:

- **Add an `'rpc'` op to the outbox** (no schema change — overload existing columns):
  `op='rpc'`, `forTable='create_pickup'`, `rowId=orderId`,
  `payloadJson={ p_customer:{…}, p_order:{…} }` (both in one row → mirrors the RPC's atomicity, one
  outbox row per pickup, dedup anchor = `create_pickup:rpc:<orderId>`).
- **Extend `OutboxWorker.supabaseDispatcher`** with an `rpc` branch that calls
  `client.rpc('create_pickup', params: payload)`. The dispatcher does **not** need the RPC's return
  value: reconciliation of the real minted `order_code` onto the local placeholder row happens via the
  **puller** pulling the now-synced server row back (its `insertOrReplace` on the same `id` overwrites
  the placeholder — see Problem 2). This is simpler than a `reconcile(orderId, orderCode)` callback
  wired into the dispatcher, and it's what shipped. (An earlier draft of this plan proposed the
  callback; the puller pull-back subsumes it.)
- **Placeholder code:** create the local order with a blank `order_code`. `LaundryOrder.orderCode`
  already falls back to `orderId` when blank, so the placeholder mechanism is half-built. The UI shows
  a friendly "New order (pending sync)" instead of the raw UUID (Gap B below).
- **Idempotency (triple-guarded):** the New Pickup screen caches `_pendingOrderId` across retries →
  same dedup key → `insertOrIgnore` no-ops the second enqueue; local upsert is idempotent on id; the
  RPC is idempotent on `p_order->>'id'` (returns existing code, does **not** throw). A double-tap or
  lost-ack retry cannot duplicate.

### Problem 2 — local (unsynced) rows coexisting with pulled server rows
The client generates `orderId` (UUID) and the RPC is idempotent on it → exactly one row identity across
local and server. Before sync there is no server row to clobber the local one. After sync, the puller's
`insertOrReplace` on the same id *is* the correct reconciliation (placeholder → real code). The only
hazard is a transient flicker if the puller pulls a pre-edit server row before a queued `update`
drains — it self-heals within one worker cycle (5s). **v1: accept the flicker** (matches the existing
last-writer-wins model); add a puller guard only if field testing shows it's objectionable.

## Other writes — RLS verification (already fine, except one)
`updateStatus`/`updateOrderDetails`/`updatePricing`/`softDelete` route as `orders:update` (drivers are
allowed direct `orders_update`); `proof_events:insert` is allowed for riders. The **one trap**:
`CustomersRepository.upsertCustomer` in the preserved OFFLINE block enqueues a raw `customers:insert`,
which a driver **cannot** write directly (customers_write RLS). The New Pickup flow avoids this (it goes
through `create_pickup`), but a *standalone* driver customer edit would dead-letter.
**Decision (recommended default): UI-restrict standalone customer edits to manager role** and document
it; revisit with an `upsert_customer` SECURITY DEFINER RPC only if drivers need standalone customer
edits. This is the only item that *might* need a new Supabase migration — deferred, not planned.

## Phased rollout (each phase independently shippable; TDD, one commit per task)

**Phase 1 — Client resilience (ships in online-only mode).** Add a global timeout to the Supabase HTTP
client so a dead network fails fast instead of hanging. Durable: covers reads (puller), RPCs, and writes,
and survives into offline mode. Implemented as a `TimeoutHttpClient` wrapper passed to
`Supabase.initialize(httpClient: ...)`. A `TimeoutException` is already classified transient by
`isTransientSyncError`, so timed-out queued writes skip without penalty once the outbox is live.
Files: `lib/src/bootstrap/app_bootstrap.dart` (+ new `lib/src/bootstrap/timeout_http_client.dart`).

**Phase 2 — Re-open local DB + reads-from-local.** Restore each repo's OFFLINE `watch*` (Drift reads):
`orders`, `customers`, `proof_events`, `status_events`, `staff`. Uncomment the DB open/seed in
bootstrap (seed through the `appDatabaseProvider` instance — avoid a second native handle). Wire
`SyncOrchestrator` + `ConnectivityWatcher` + `onlineProvider` via `ref.watch(syncLifecycleProvider)`
in `main.dart`. Restore the `SyncPuller` so the local DB fills from the server. Un-skip
`test/sync_puller_test.dart`, `test/end_to_end_sync_test.dart`. Reads now come from disk; writes still
go straight to Supabase this phase.
Files: `lib/src/sync/repository_providers.dart`, `lib/src/bootstrap/app_bootstrap.dart`,
`lib/main.dart`, the five `*_repository.dart` read paths.

**Phase 3 — Order/status/proof writes through the outbox.** This is the heart of the fix.
- Restore the OFFLINE write bodies (Drift insert + `outbox.enqueue`) for orders/customers/proof/status.
- Implement **Problem 1**: add the `rpc` op + dispatcher branch (reconciliation is handled by the
  puller pulling the synced row back, not a dispatcher callback); offline `createPickup` writes local
  placeholder + enqueues the `create_pickup` rpc row.
- Add the offline methods missing from the preserved block: `updateOrderDetails`, `updatePricing`,
  `softDelete` (all as `orders:update`).
- Restore sign-out teardown (`orchestrator.stop()` + local truncate) in `lib/src/auth/sign_out.dart`
  and its caller.
Files: `lib/src/sync/orders_repository.dart`, `lib/src/sync/outbox_worker.dart`,
`lib/src/sync/sync_orchestrator_provider.dart`, `lib/src/sync/{customers,proof_events,status_events}_repository.dart`,
`lib/src/auth/sign_out.dart`.

**Phase 4 — Durable photos (Gap A).** Photos are in-memory only today → lost on restart, never durably
uploaded. Infrastructure already exists: `FileProofPhotoStorage` (writes compressed JPEGs to disk, is
tested), the Drift `ProofPhotos` table, the server `proof_photos` table + RLS, and a **private
`proof-photos` Storage bucket** (`0004`/`0007`/`0008`) — **no new migration needed**. Add:
- `lib/src/orders/proof/proof_photos_repository.dart` — Drift CRUD (`insertLocal`, `watchPendingUploads`, `markUploaded`).
- `lib/src/sync/photo_upload_worker.dart` — mirrors `OutboxWorker`; drains `proof_photos WHERE uploaded_at IS NULL`,
  uploads bytes via injected `PhotoUploader` (prod = `client.storage.from('proof-photos').uploadBinary(key, bytes, upsert:true)`),
  then `markUploaded` + enqueues the server `proof_photos` row through the existing outbox. Remote key must
  start with `proof/`: `proof/<orderId>/<eventId>/<photoId>.jpg`.
- Persist photo rows inside `insertEvent`'s transaction; swap `InMemoryProofPhotoStorage` → file storage
  at `staff_dashboard_screen.dart:95`; start the photo worker in `SyncOrchestrator`; fold pending-photo
  count into sync status.
- Treat auth (401) failures as **transient-retryable** so re-auth recovers uploads.

**Phase 5 — UX (Gap B): optimistic + visible sync state.** Mount `SyncStatusBanner` in
`_DashboardTabShell`; restore the AppBar sync-errors badge + `_openSyncErrors` (→ `SyncErrorsScreen`);
add a per-card "pending sync" chip (`order_card.dart`, sourced from a `pendingOrderIdsProvider` over
`outbox` rows); show friendly placeholder for orders without a server code yet (add
`bool get hasServerCode => orderCode != orderId;`); route tag-print guidance to "code assigned once
synced" so a rider never writes a UUID on a bag. Drop the New Pickup 2-second polling hack — local
reads make the new order appear synchronously.
Files: `lib/src/dashboard/staff_dashboard_screen.dart`, `lib/src/orders/widgets/order_card.dart`,
`lib/src/orders/widgets/order_card_list.dart`, `lib/src/orders/order.dart`.

**Phase 6 — Coverage + hardening.** Un-exclude `sync_puller|outbox_worker|sync_orchestrator` from
`coverage/summary.sh` (now live + tested), drive testable surface back to ~98%, add post-upload local
photo cleanup (delete the JPEG only after **both** the Storage upload **and** the server row insert are
confirmed sent), cap per-order photos (already `_maxPhotos=3`).

## Critical files
- `lib/src/sync/orders_repository.dart` — offline body + `createPickup`/updates/softDelete
- `lib/src/sync/outbox_worker.dart` — new `rpc` op branch in `supabaseDispatcher` (puller reconciles `order_code`)
- `lib/src/sync/sync_orchestrator_provider.dart` — wire the dispatcher (no reconcile callback needed)
- `lib/src/sync/repository_providers.dart` — rewire 5 repos from `SupabaseClient` → Drift + outbox
- `lib/src/bootstrap/app_bootstrap.dart` + `lib/main.dart` — open DB/seed, timeouts, `ref.watch(syncLifecycleProvider)`
- `lib/src/sync/photo_upload_worker.dart` (new) + `lib/src/orders/proof/proof_photos_repository.dart` (new)
- `lib/src/dashboard/staff_dashboard_screen.dart`, `lib/src/orders/widgets/order_card.dart` — UX
- `lib/src/auth/sign_out.dart` — restore teardown

## Risks & notes
- **Drift re-open:** filename is `amuwak_staff.sqlite`, schema v6, unchanged → no migration bump. Fresh
  devices run `onCreate` cleanly and repopulate via the puller's `_epoch` watermark. First launch shows
  a briefly-empty dashboard until the first `pullAll` (~15s) — mitigated by the seed + banner "syncing…".
- **Half-enabled ordering is dangerous:** enabling local reads (P2) without the puller → empty dashboard;
  file storage (P4) without the upload worker → silent photo data loss; banner (P5) before outbox writes
  (P3) → dead "0 pending". Enforce phase order strictly; each phase's tests gate the next.
- **Customer-upsert RLS trap** (above) — default to UI-restricting standalone driver customer edits.
- **No new Supabase migration required** for the planned scope (`create_pickup`, `proof_photos`, bucket
  all already exist). Contingency migrations only: `upsert_customer` RPC (if drivers need standalone
  customer edits) and a `proof_photos_insert` RLS tweak (only if the client-inserted row fails the
  self-attribution policy — verify in P4).

## Verification
- **Unit (TDD, one test file at a time — multi-path `flutter test` hangs on this Windows host):**
  `flutter test test/outbox_worker_test.dart` (new `rpc`-op case), `.../orders_repository_mutations_test.dart`
  (offline create/update + dedup), `.../photo_upload_worker_test.dart`,
  `.../proof_photos_repository_test.dart`, un-skipped `test/end_to_end_sync_test.dart` +
  `test/sync_puller_test.dart` (placeholder → real `order_code` reconciliation via the puller), and
  the UX widget tests (`order_card`, dashboard banner/badge).
- **Coverage:** `flutter test --coverage && bash coverage/summary.sh` back to ~98% after Phase 6.
- **Manual acceptance (the real fix):** turn connectivity **off** → Create pickup → order appears
  instantly with a "pending sync" chip and friendly code → turn connectivity **on** → within one worker
  cycle the real `AMW-…` code backfills and pending drops to 0 → **kill & relaunch offline mid-queue** →
  the outbox row survives and drains on reconnect → capture a proof photo offline → it uploads to the
  `proof-photos` bucket when signal returns.
