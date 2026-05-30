# Plan 3a — Sync Foundation: Repositories + Orchestrator + Banner

## Context

Plan 1 (`2026-05-18-supabase-database-foundation.md`) shipped the Supabase Postgres schema. Plan 2 (`2026-05-19-drift-outbox-sync-layer.md`) shipped the on-device Drift database, the outbox, the puller, the connectivity watcher, the sync-status provider, and the banner widget — but only the **mechanics**. Nothing currently calls them: no repositories sit on top of Drift, the worker/puller never start, the banner isn't mounted, and the dashboard still renders a hardcoded `List<LaundryOrder>` in `lib/src/dashboard/staff_dashboard_screen.dart`.

The original spec scoped Plan 3 as "wire existing UI screens to the new repositories." That's too big for one plan; the user split it. **Plan 3a (this plan)** is the foundation: repositories, the orchestrator that starts/stops the sync engine with the auth lifecycle, the missing puller mappers, and mounting the already-built `SyncStatusBanner`. **Plan 3b (next plan)** swaps the dashboard and the other screens to consume the repositories and adds the capture-screen outbox writes for status transitions. **Plan 4** handles the photo upload path.

Outcome of this plan: every piece behind the banner works end-to-end on a logged-in device — pull populates Drift, the orchestrator starts on sign-in and stops on sign-out, the banner shows real pending counts and a real `lastSyncedAt`. No screen behavior visibly changes except for the banner appearing at the top of the dashboard.

## Up-front decisions (already confirmed with user)

- **Plan size:** Plan 3a foundation only. Dashboard list stays in-memory until 3b.
- **Domain bridge:** Keep `LaundryOrder` (`lib/src/orders/order.dart`) and add a `LaundryOrder.fromDriftRow` mapper. Smallest churn for Plan 3b.
- **Missing puller mappers:** Add code for all 5 (`order_status_events`, `proof_photos`, `issues`, `shifts`, `valid_transitions`). Only the first two are added to `kSyncTables` in this plan; `issues`/`shifts` need a Postgres `updated_at` migration first (deferred), and `valid_transitions` is a one-shot bootstrap fetch (not periodic).
- **Capture screens:** No outbox writes in 3a. Plan 3b wires status transitions; photos stay `InMemoryProofPhotoStorage` until Plan 4.

## Architecture

```
main.dart
  └── ProviderScope
      └── Consumer (watches syncLifecycleProvider)
          └── MaterialApp
              └── ... screens ...
                  └── StaffDashboardScreen
                      └── SyncStatusBanner  ← mounted in 3a

syncLifecycleProvider listens to authStateProvider:
  signed in  → syncOrchestrator.start()
  signed out → syncOrchestrator.stop()

SyncOrchestrator owns:
  - OutboxWorker (drains outbox every 5s)
  - SyncPuller   (pulls every 15s + on online edge)
  - ConnectivityWatcher (drives onlineProvider, triggers pull-on-reconnect)
  - ValidTransitionsLoader (one-shot fetch after first start)

Repositories wrap AppDatabase:
  OrdersRepository       → Stream<List<LaundryOrder>> / Stream<LaundryOrder?>
  CustomersRepository    → Stream<List<Customer>>     (Drift row)
  StaffRepository        → Stream<List<StaffData>>    (Drift row)
  ProofEventsRepository  → Stream<List<ProofEvent>>   (Drift row)
  StatusEventsRepository → Stream<List<OrderStatusEvent>> (Drift row)
```

Why a separate `SyncOrchestrator` instead of methods on `AppBootstrap`: `AppBootstrap` is a one-shot static; the orchestrator must `start()`/`stop()` on auth-state edges, which is a lifecycle concern with its own test surface.

## Critical files

| File | What |
|---|---|
| `lib/src/orders/order.dart` | add `LaundryOrder.fromDriftRow` factory |
| `lib/src/sync/orders_repository.dart` *(new)* | `watchAll`, `watchById` returning `LaundryOrder` |
| `lib/src/sync/customers_repository.dart` *(new)* | returns Drift rows |
| `lib/src/sync/staff_repository.dart` *(new)* | returns Drift rows |
| `lib/src/sync/proof_events_repository.dart` *(new)* | returns Drift rows |
| `lib/src/sync/status_events_repository.dart` *(new)* | append-only reads |
| `lib/src/sync/repository_providers.dart` *(new)* | Riverpod providers for all five repos |
| `lib/src/sync/sync_registry.dart` | add `watermarkColumn` field |
| `lib/src/sync/sync_puller.dart` | use registry's `watermarkColumn`; 5 new mappers + switch cases |
| `lib/src/sync/valid_transitions_loader.dart` *(new)* | one-shot full-table fetch |
| `lib/src/sync/sync_orchestrator.dart` *(new)* | lifecycle; owns worker/puller/watcher |
| `lib/src/sync/connectivity_watcher.dart` | extend `start` with `onOffline` callback |
| `lib/src/sync/sync_status.dart` | `lastSyncedAt` from `sync_watermarks.MAX(last_synced_at)` |
| `lib/src/dashboard/staff_dashboard_screen.dart` | mount `SyncStatusBanner`, convert to `ConsumerStatefulWidget` |
| `lib/src/auth/sign_out.dart` *(new)* | stop orchestrator + truncate Drift + sign out |
| `lib/main.dart` | mount `syncLifecycleProvider` consumer |

Reuse: `OutboxRepository` (`lib/src/sync/outbox_repository.dart`), `OutboxWorker.supabaseDispatcher`, `SyncPuller.supabaseFetcher`, `appDatabaseProvider`, `authStateProvider` are all already in place and remain unchanged in shape.

---

## Task list

Each task = one commit. TDD: red test first, then implementation, then verification.
Use scoped `git commit -- <paths>` per existing memory rule (don't bundle the user's pre-staged work).

### Task 1 — `LaundryOrder.fromDriftRow` mapper

- **Test:** `test/orders/order_from_drift_row_test.dart` *(new)*
  - 4 status strings → 4 `OrderStatus` enum values; unknown string throws `StateError`.
  - `timeLabel` derived from `scheduled_for` if present, otherwise from `created_at`.
  - 2 proof events of different `type` strings map to 2 domain `ProofEvent`s with `photoPaths: const []` (photos deferred to Plan 4).
  - Empty `proofEvents` argument → `LaundryOrder.proofEvents.isEmpty`.
- **Modify:** `lib/src/orders/order.dart` — add `factory LaundryOrder.fromDriftRow(Order driftOrder, List<ProofEvent> driftEvents)`. Import `app_database.dart` with an alias `as drift` to avoid the `ProofEvent` name collision with `lib/src/orders/proof_event.dart`.
- **Verify:** `flutter test test/orders/order_from_drift_row_test.dart`; existing `test/orders/order_test.dart` still passes.

### Task 2 — `OrdersRepository`

- **Test:** `test/sync/orders_repository_test.dart` *(new)*
  - Uses `AppDatabase.forTesting(NativeDatabase.memory())` (pattern already in `test/sync_puller_test.dart`).
  - Empty DB → `watchAll()` emits `[]`.
  - Insert 2 orders + 2 proof events for order A → `watchAll()` emits a list where order A has 2 proof events and order B has 0.
  - Updating order A's `status` re-emits with the new status.
  - `watchById('missing')` emits `null`; `watchById(existingId)` emits a `LaundryOrder` with its proof events.
- **Create:** `lib/src/sync/orders_repository.dart`. `watchAll()` runs Drift's `select(orders).watch()` then for each emission resolves proof events via a second `(select(proofEvents)..where(t => t.orderId.isIn([...]))).get()` and maps via `LaundryOrder.fromDriftRow`. Avoid a single join+watch — Drift returns flat rows on joined streams and grouping inside a `.watch()` reducer is fragile.
- **Verify:** new test green.

### Task 3 — `CustomersRepository`, `StaffRepository`

- **Test:** `test/sync/customers_repository_test.dart` *(new)* + `test/sync/staff_repository_test.dart` *(new)*
  - `watchAll()` excludes soft-deleted rows (`deletedAt IS NOT NULL`).
  - Ordering: customers by `name`, staff by `displayName`.
  - `watchById(id)` returns the row or null.
- **Create:** `lib/src/sync/customers_repository.dart`, `lib/src/sync/staff_repository.dart` — return raw Drift row classes (`Customer`, `StaffData`).
- **Verify:** new tests green.

### Task 4 — `ProofEventsRepository`, `StatusEventsRepository`

- **Test:** `test/sync/proof_events_repository_test.dart` *(new)* + `test/sync/status_events_repository_test.dart` *(new)*
  - `watchByOrder(orderId)` returns only events for that order, ordered by `capturedAt` / `changedAt`.
  - `StatusEventsRepository` has no `update` or `delete` method (append-only contract).
- **Create:** `lib/src/sync/proof_events_repository.dart`, `lib/src/sync/status_events_repository.dart`.
- **Verify:** new tests green.

### Task 5 — Riverpod providers for all five repositories

- **Test:** `test/sync/repository_providers_test.dart` *(new)*
  - `ProviderContainer` with `appDatabaseProvider` overridden to in-memory; resolve each repo provider; second read returns the same instance (singleton via `Provider`).
- **Create:** `lib/src/sync/repository_providers.dart` — exports `ordersRepositoryProvider`, `customersRepositoryProvider`, `staffRepositoryProvider`, `proofEventsRepositoryProvider`, `statusEventsRepositoryProvider`.
- **Verify:** new test green.

### Task 6 — Per-table watermark column in `SyncPuller`

- **Test:** `test/sync_puller_test.dart` *(modify)* — add `"pullTable uses configured watermark column"`.
  - Register a test `SyncTable(name: 'order_status_events', watermarkColumn: 'changed_at')`.
  - Feed rows with only `changed_at` (no `updated_at`); confirm watermark advances and rows land.
  - Existing default-column tests still pass.
- **Modify:**
  - `lib/src/sync/sync_registry.dart` — add `final String watermarkColumn` with default `'updated_at'`. Existing `const SyncTable(name: ...)` literals continue to compile.
  - `lib/src/sync/sync_puller.dart` — `supabaseFetcher` consults the registry for the column; `pullTable` reads `row[watermarkColumn]` when advancing `maxUpdated`.
- **Verify:** `flutter test test/sync_puller_test.dart` all green.

### Task 7 — Mappers + switch cases for the 5 missing tables

- **Test:** `test/sync_puller_test.dart` *(modify)* — one parametric block per table (`order_status_events`, `proof_photos`, `issues`, `shifts`, `valid_transitions`).
  - For each: call `pullTable` against a single-row fixture; assert the row lands in the corresponding Drift table.
  - Cover nullable columns: `order_status_events.from_status`/`device_event_id`; `proof_photos.width`/`height`/`bytes`/`uploaded_at`; `issues.order_id`/`resolved_at`/`resolved_by`; `shifts.lat`/`lng`/`ended_at`; `valid_transitions.from_status`.
- **Modify:** `lib/src/sync/sync_puller.dart` — add 5 mappers (`_orderStatusEventsFromJson`, `_proofPhotosFromJson`, `_issuesFromJson`, `_shiftsFromJson`, `_validTransitionsFromJson`) and 5 switch cases. After this task, `_upsertRow` no longer throws `StateError` for any of the 11 schema tables.
- **Verify:** new test cases green.

### Task 8 — Activate `order_status_events` + `proof_photos` in `kSyncTables`

- **Test:** `test/sync_puller_test.dart` *(modify)* — `pullAll()` test asserts watermarks are written for both new tables. Use a fake fetcher that returns deterministic rows; assert both watermark rows exist post-pull.
- **Modify:** `lib/src/sync/sync_registry.dart` — append:
  - `SyncTable(name: 'order_status_events', watermarkColumn: 'changed_at')`
  - `SyncTable(name: 'proof_photos', watermarkColumn: 'created_at')`
  - Update the doc comment: explain why `issues`/`shifts` stay off (need Postgres `updated_at` migration in a future plan) and why `valid_transitions` stays off (loaded once via the loader, not periodic).
- **Verify:** new test green. Existing `test/end_to_end_sync_test.dart` against live creds still works (manual smoke; not gated in CI).

### Task 9 — `ValidTransitionsLoader` (one-shot bootstrap fetch)

- **Test:** `test/sync/valid_transitions_loader_test.dart` *(new)*
  - Fake `SyncFetch` returning 12 rows → `loadOnce()` writes all 12 into Drift.
  - Calling `loadOnce()` again with new fetcher → table is replaced (idempotent via `insertOnConflictUpdate`).
  - Fetcher throws → DB unchanged (loader rethrows; no partial write).
  - Does NOT touch `sync_watermarks` (intentional — this is a static-seed table).
- **Create:** `lib/src/sync/valid_transitions_loader.dart` — class with `Future<void> loadOnce()` using the same `SyncFetch` contract.
- **Verify:** new test green.

### Task 10 — Extend `ConnectivityWatcher` with `onOffline`

- **Test:** `test/sync/connectivity_watcher_test.dart` *(new — or extend existing)*
  - Simulate a connectivity stream emitting `[wifi] → [none] → [wifi]`; `onOnline` fires twice, `onOffline` fires once.
  - `start()` is idempotent: a second `start()` cancels and re-installs the subscription.
- **Modify:** `lib/src/sync/connectivity_watcher.dart` — `start({required void Function() onOnline, void Function()? onOffline})`.
- **Verify:** new test green. (Needed by `SyncOrchestrator` to drive `onlineProvider` both directions.)

### Task 11 — `SyncOrchestrator`

- **Test:** `test/sync/sync_orchestrator_test.dart` *(new)* — mocktail mocks of `OutboxWorker`, `SyncPuller`, `ConnectivityWatcher`, `ValidTransitionsLoader`, plus a `ProviderContainer` with `onlineProvider` watchable.
  - `start()` calls `worker.start(...)`, kicks off an immediate `puller.pullAll()`, calls `transitions.loadOnce()` once, registers connectivity callbacks, sets `onlineProvider` from `watcher.isOnline()`.
  - Online edge fired → `puller.pullAll()` runs again; `onlineProvider` becomes `true`.
  - Offline edge fired → `onlineProvider` becomes `false`; puller is NOT called.
  - Second `start()` is a no-op (idempotent).
  - `stop()` calls `worker.stop()`, cancels the periodic-pull timer, calls `watcher.dispose()`, awaits any in-flight `drainOnce()` (orchestrator tracks `_inflight: Future?`).
- **Create:** `lib/src/sync/sync_orchestrator.dart` — constructor:
  ```dart
  SyncOrchestrator({
    required AppDatabase db,
    required OutboxWorker worker,
    required SyncPuller puller,
    required ConnectivityWatcher watcher,
    required ValidTransitionsLoader transitions,
    required Ref ref,
    Duration workerInterval = const Duration(seconds: 5),
    Duration pullerInterval = const Duration(seconds: 15),
  });
  ```
  Holds a separate `Timer.periodic` for the pull cadence (different from the worker's drain cadence). Exposes `start()`, `stop()`, `Future<void> syncNow()`.
- **Verify:** new test green.

### Task 12 — `syncOrchestratorProvider` + auth-driven `syncLifecycleProvider`

- **Test:** `test/sync/sync_orchestrator_wiring_test.dart` *(new)*
  - `ProviderContainer` with `authStateProvider` overridden to a `StreamController`-backed source.
  - Initial state signed-out → orchestrator `start()` NOT called.
  - Emit signed-in `AuthState` → `start()` called once.
  - Emit signed-out → `stop()` called once.
  - Emit signed-in again → `start()` called once more.
  - Container dispose → `stop()` called.
- **Create:** in `lib/src/sync/sync_orchestrator.dart` (or `lib/src/sync/sync_orchestrator_provider.dart`):
  - `syncOrchestratorProvider = Provider<SyncOrchestrator>(...)` constructs the orchestrator via `appDatabaseProvider` + `Supabase.instance.client` for the dispatcher and fetcher.
  - `syncLifecycleProvider = Provider<void>(...)` watches `authStateProvider` and toggles `start()`/`stop()` based on `session != null`. Use `ref.onDispose` to ensure `stop()` runs on container dispose.
- **Verify:** new test green.

### Task 13 — `lastSyncedAt` from real watermarks

- **Test:** `test/sync/sync_status_test.dart` *(new)*
  - Seed two `sync_watermarks` rows with different timestamps → `syncStatusProvider.lastSyncedAt` equals the later timestamp.
  - No watermarks → `lastSyncedAt` is `null`.
  - Add a third watermark → provider re-emits with the new max.
- **Modify:** `lib/src/sync/sync_status.dart`:
  - Add `final lastSyncedAtProvider = StreamProvider<DateTime?>((ref) { ... })` using Drift `selectOnly` + `db.syncWatermarks.lastSyncedAt.max()` and `.watchSingle()`.
  - Wire it into `syncStatusProvider`.
- **Verify:** new test green.

### Task 14 — Mount `SyncStatusBanner` in `StaffDashboardScreen`

- **Test:** `test/dashboard/staff_dashboard_screen_test.dart` *(modify or new — confirm location during impl)*
  - Pump with `ProviderScope` overriding `onlineProvider` to `false` → expect `SyncStatusBanner` to render with the offline label and the (empty) pending count.
  - Pump with `onlineProvider = true` and `pendingOutboxCountProvider` overridden to a stream emitting `3` → expect the pending-uploads label with "3".
- **Modify:** `lib/src/dashboard/staff_dashboard_screen.dart` — convert from `StatefulWidget` to `ConsumerStatefulWidget` (drop-in: `extends ConsumerStatefulWidget` / `State<...>` → `ConsumerState<...>`). Restructure the body so the banner sits above the existing scrolling content: wrap the existing body in a `Column` with `SyncStatusBanner()` as the first child and the existing `ListView` (or whatever) expanded below.
- **Verify:** new + existing dashboard tests green; no other behavior changes.

### Task 15 — `signOutAndReset` helper

- **Test:** `test/sync/sign_out_test.dart` *(new)*
  - Seed orders / customers / outbox / watermarks rows in an in-memory Drift; mock `SyncOrchestrator` and `AuthService`.
  - Call `signOutAndReset(ref)` → orchestrator `stop()` invoked → all tracked Drift tables truncated (orders, customers, staff, proof_events, proof_photos, order_status_events, issues, shifts, valid_transitions, outbox, sync_watermarks) → `AuthService.signOut()` invoked exactly once.
  - Ordering matters: `stop()` runs and awaits in-flight work BEFORE truncate; truncate runs BEFORE `signOut()`.
- **Create:** `lib/src/auth/sign_out.dart` — `Future<void> signOutAndReset(Ref ref)`. Use an explicit list of tables in code so future tables aren't silently skipped (don't introspect `db.allTables` — too magical and risks truncating a future table that shouldn't be wiped).
- **Verify:** new test green. UI wiring of a "Sign out" button is left for Plan 3b.

### Task 16 — Wire `syncLifecycleProvider` into app startup

- **Test:** `test/app_startup_test.dart` *(new)*
  - Pump `MyApp()` inside `ProviderScope` with overrides:
    - `appDatabaseProvider` → in-memory
    - `syncOrchestratorProvider` → mock orchestrator
    - `authStateProvider` → signed-out stream
  - Assert: app renders without throwing, login screen is shown, and `syncLifecycleProvider` was resolved (i.e. the consumer in main.dart actually mounted it).
- **Modify:** `lib/main.dart` — wrap `MaterialApp` (or its `home`) in a small `Consumer` / `ConsumerStatefulWidget` that calls `ref.watch(syncLifecycleProvider)`. `AppBootstrap.initialize()` stays as one-line Supabase init — orchestrator lifecycle is a UI-tree concern, not a startup-script concern, because it depends on `Ref` and the Riverpod container.
- **Verify:** new test green. Manual smoke (post-merge, optional): `flutter run` with valid `--dart-define` creds; sign in; banner clears; toggle airplane mode; banner turns orange; toggle back; banner clears + `sync_watermarks.last_synced_at` advances on next pull.

---

## Verification (end-to-end after all tasks)

1. `flutter analyze` — clean (no new warnings).
2. `flutter test` — all tests pass, including pre-existing ones (`test/end_to_end_sync_test.dart` skip-condition unchanged).
3. Manual smoke against a running Supabase instance:
   - `flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`
   - Sign in with a seeded staff user. Within ~1s the banner should clear (pending = 0, online = true).
   - Open SQLite browser on the device DB: confirm `orders`, `customers`, `staff`, `proof_events`, `order_status_events`, `proof_photos`, `sync_watermarks`, and `valid_transitions` are populated.
   - Toggle airplane mode: banner turns orange ("Offline — 0 pending"); turn off airplane mode: banner clears and `sync_watermarks.last_synced_at` advances on the next 15s tick (or sooner via the connectivity edge trigger).
   - Sign out (via debug tool or new `signOutAndReset` from a test harness — there's no UI button yet): orchestrator stops; Drift truncated; login screen shown.

## What this plan does NOT do (explicitly forwarded)

- **Dashboard does not bind to `OrdersRepository`.** Hardcoded list in `StaffDashboardScreen` stays. Plan 3b swaps it to `ref.watch(ordersRepositoryProvider).watchAll()`.
- **Other screens unchanged.** `OrderDetailsScreen`, `PickupCaptureScreen`, `DeliveryCaptureScreen`, `ScannerScreen`, `DailyReportScreen`, `OrderSearchScreen`, `NewPickupScreen`, `NotificationsScreen`, `LoginScreen` — Plan 3b.
- **No outbox writes from UI.** Status transitions and proof captures still mutate widget-local state. Plan 3b adds `OutboxRepository.enqueue(...)` calls when the capture screens are rewritten.
- **No photo upload.** `InMemoryProofPhotoStorage` remains. `proof_photos` rows are pulled (read-only on device) but not written by the client. Plan 4 builds the upload path.
- **`issues` / `shifts` not synced.** Their mappers exist (Task 7) but they stay off `kSyncTables` until a small future plan adds `updated_at` columns + triggers to the Postgres schema.
- **No realtime / push.** Pull is polled (15s) + on connectivity edge. Realtime is a later optimization.
- **No background sync.** App-suspended state pauses timers; resume triggers a pull via the connectivity-watcher edge or via the next periodic tick.
- **No dead-letter UI.** Outbox rows that fail 5× still log to console; surfacing them is a future plan.
- **No "Sign out" button wired into UI.** `signOutAndReset` exists and is tested; Plan 3b adds the button to the dashboard / settings screen.

## Risks

1. **Drift `.watch()` over joins.** Joined streams emit flat rows. `OrdersRepository.watchAll` deliberately does two separate watches (`orders.watch()` → for each emission, `(proofEvents.where(orderId.isIn(ids))).get()`) rather than one joined `.watch()`. Tradeoff: ~one extra query per emission; benefit: trivial mental model + no grouping bug.
2. **First-login RLS race.** Right after sign-in, `pullAll()` may run before the JWT-claim hook (Supabase migration 0009) has propagated to the client, returning `[]` silently. Orchestrator's `start()` should verify `Supabase.instance.client.auth.currentSession?.accessToken != null` and await a brief `Future.delayed(Duration(milliseconds: 250))` before the first pull. Log per-table pulled-row counts so a silent empty first sync is visible in dev.
3. **`ProofEvent` name collision.** Drift generates a `ProofEvent` row class in `app_database.g.dart` that conflicts with the domain `ProofEvent` in `lib/src/orders/proof_event.dart`. Files that need both must use an import alias (`import 'package:.../app_database.dart' as drift;` and reference `drift.ProofEvent`).
4. **`SyncTable` const compatibility.** Adding a `watermarkColumn` field with a string default (`'updated_at'`) preserves existing `const SyncTable(name: ...)` literals. Do NOT mark the new param non-default or use a non-const default — that breaks the const list.
5. **Sign-out vs in-flight worker.** `signOutAndReset` must `await orchestrator.stop()` (which itself awaits any in-flight `drainOnce`) BEFORE truncating Drift, otherwise the worker may write to a soon-to-be-empty DB. Orchestrator's `stop()` should track a `_drainInFlight: Future?` and await it.
6. **Idempotent `start()`.** Second `syncLifecycleProvider` evaluation must not double-start the orchestrator. Test 11 covers idempotency directly.
7. **Connectivity edge ordering.** `ConnectivityWatcher.start` is currently online-only; Task 10 adds offline-edge support. Make sure existing call sites of `start()` (none in production code yet, only tests) still compile because `onOffline` is optional.
8. **`order_status_events` poison rows.** Plan 2's batch-abort behavior means a single malformed row blocks the whole batch and keeps it at the head of every subsequent pull. Plan 3a inherits this; add a `// TODO: pull-side dead-letter` comment in `_upsertRow` for the case so it's not forgotten.
9. **Test isolation.** Every Drift test must `setUp` a fresh `NativeDatabase.memory()` and `tearDown` close it — pattern already in `test/sync_puller_test.dart`. Sharing a DB across tests in this plan would cause watermark bleed.
10. **Banner placement.** `StaffDashboardScreen` body is currently a `ListView` directly under `SafeArea`. Wrapping in `Column` + `Expanded(child: ListView)` must preserve scroll physics and pull-to-refresh (if any). Test 14 includes a smoke check.
