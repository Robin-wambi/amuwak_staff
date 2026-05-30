# Orders-Stream Migration — Design (2026-05-18)

## Status
Draft — pending user review

## Summary
Migrate the dashboard from its hardcoded in-memory `_orders` list to a Drift-backed stream sourced through `OrdersRepository.watchAll()` via a Riverpod `StreamProvider`. Update the three proof-capture screens (`OrderDetailsScreen`, `PickupCaptureScreen`, `DeliveryCaptureScreen`) to write their changes to the local Drift database + outbox before popping, so the dashboard's stream picks them up. Seed the four existing fixture orders into the local DB on first launch so the dashboard isn't empty.

This is PR-A in a two-PR sequence. PR-B (the New Pickup form) will sit on top of this and reuse the same write path.

## Problem
The backend rails (`AppDatabase`, `OrdersRepository`, `OutboxRepository`, `OutboxWorker`, `SyncOrchestrator`, `SupabaseClient`) all exist on this branch, but no UI screen reads from or writes through them. The dashboard still holds a `final List<LaundryOrder> _orders = [const LaundryOrder(...), ...]` literal and mutates it in `setState`. The proof-capture screens still pop an updated `LaundryOrder` back to the dashboard, which then swaps it into the in-memory list. As long as that's the case, **any feature added on top of the new backend layer will have two sources of truth** — Drift on one side, the dashboard's `_orders` on the other — and writes won't show up where reads happen.

The New Pickup feature (PR-B) is blocked on closing this gap.

## Goal
- The dashboard reads its order list exclusively from `OrdersRepository.watchAll()` via Riverpod.
- The three proof-capture screens write their changes through `OrdersRepository` + `ProofEventsRepository` (which enqueue outbox rows for sync to Supabase). They no longer return data through `Navigator.pop`.
- A first-launch seed routine populates the four existing fixture orders into the local Drift DB so manual testing works from the first run.
- All existing widget tests continue to pass after migration. Tests use an in-memory `AppDatabase` injected via Riverpod overrides.

## Non-Goals
- **Not converting the capture screens to `ConsumerWidget`.** They keep their `StatefulWidget` shape and their existing constructor-injected dependencies (`photoStorage`, `pickPhoto`, `clock`, `cameraViewBuilder`). Two new constructor params (`ordersRepo`, `proofEventsRepo`) are added; that's the only API change.
- **Not building the New Pickup form.** Deferred to PR-B.
- **Not syncing fixture orders to Supabase.** Seed rows are local-only — no outbox enqueue. Each rider's local DB is independently seeded.
- **No new Riverpod providers beyond what this migration needs.** Specifically: `ordersStreamProvider`, plus reuse of the existing `appDatabaseProvider`, `outboxRepositoryProvider`, and per-entity repository providers from `lib/src/sync/repository_providers.dart`.
- **No outbox-drain-on-write.** Writes enqueue; the existing periodic `OutboxWorker` drains.
- **No schema changes.** The existing `orders` and `proof_events` Drift tables already have everything needed.
- **No conversion of `LaundryOrder` to a Drift-native row type.** `LaundryOrder` stays as the domain model; the existing `LaundryOrder.fromDriftRow(row, events)` factory is the only adapter.

## Decisions Locked In
1. **Dashboard only** is migrated to Riverpod; the capture screens stay on `StatefulWidget` with constructor injection. Smallest migration that closes the parallel-truth gap.
2. **Capture screens write to Drift before popping**; the pop now signals "done navigating," not "here's the new data."
3. **Seed orders are local-only** — no outbox enqueue. Each rider has independent demo data; production Supabase isn't polluted.
4. **`StreamProvider<List<LaundryOrder>>`** is the read API for the dashboard. Loading state shows an empty `ListView` (matching today's "no orders" rendering); error state shows a SnackBar via `ref.listen` and a centered error message.
5. **Writes are atomic per logical change.** `OrdersRepository.upsertOrder` wraps the Drift insert/update + outbox enqueue in a single `_db.transaction`. Same for `OrdersRepository.updateStatus` and `ProofEventsRepository.insertEvent`. A crash mid-write leaves the local row and the outbox row consistent.

## Data Model (no changes — existing schema)

`orders` table ([lib/src/data/tables/orders_table.dart](lib/src/data/tables/orders_table.dart)):
- `id`, `orderCode`, `customerId?`, `customerName`, `phone`, `address`, `serviceType`, `status`, `intakeMethod`, `fulfillmentMethod`, `itemCount`, `notes`, `scheduledFor?`, `assignedDriver?`, `intakeRecordedBy`, `createdBy`, `createdAt`, `updatedAt`, `deletedAt?`.

`proof_events` table ([lib/src/data/tables/proof_events_table.dart](lib/src/data/tables/proof_events_table.dart)) — already in use by `OrdersRepository.watchAll` join.

`outbox` table ([lib/src/data/tables/outbox_table.dart](lib/src/data/tables/outbox_table.dart)) — already in use by `OutboxRepository`.

## File Layout

```
lib/src/
  data/
    orders_seeder.dart                  (new)
  sync/
    orders_repository.dart              (modified — add upsertOrder, updateStatus)
    proof_events_repository.dart        (modified — add insertEvent)
    repository_providers.dart           (modified — add ordersStreamProvider)
  bootstrap/
    app_bootstrap.dart                  (modified — call OrdersSeeder.seedIfEmpty)
  dashboard/
    staff_dashboard_screen.dart         (modified — ConsumerStatefulWidget, watch ordersStreamProvider, drop _orders + _replaceUpdatedOrder)
  orders/
    order_details_screen.dart           (modified — accept ordersRepo, write status update on advance)
    proof/
      pickup_capture_screen.dart        (modified — accept ordersRepo + proofEventsRepo, write before pop)
      delivery_capture_screen.dart      (modified — accept ordersRepo + proofEventsRepo, write before pop)

test/
  data/
    orders_seeder_test.dart             (new)
  sync/
    orders_repository_write_test.dart   (new)
    proof_events_repository_write_test.dart (new)
    orders_stream_provider_test.dart    (new)
  dashboard/
    staff_dashboard_screen_test.dart    (modified — pump with ProviderScope + in-memory db; remove _orders-prop assertions)
  orders/
    order_details_screen_test.dart      (modified — assert DB row changed instead of popped order)
    proof/
      pickup_capture_screen_test.dart   (modified — assert DB row changed instead of popped order)
      delivery_capture_screen_test.dart (modified — assert DB row changed instead of popped order)
```

## Components

### `OrdersRepository` write methods (`lib/src/sync/orders_repository.dart`)

```dart
Future<void> upsertOrder(LaundryOrder order, {required String actorStaffId}) async {
  await _db.transaction(() async {
    final companion = _toCompanion(order, actorStaffId);
    await _db.into(_db.orders).insertOnConflictUpdate(companion);
    await _outbox.enqueue(
      id: _uuid(),                              // see id-generation below
      forTable: 'orders',
      op: 'insert',                             // upsert maps to insert at the outbox; the worker uses Supabase's upsert
      rowId: order.id,
      payload: _toPayload(order),
    );
  });
}

Future<void> updateStatus(String orderId, OrderStatus newStatus,
    {required String actorStaffId}) async {
  await _db.transaction(() async {
    await (_db.update(_db.orders)..where((t) => t.id.equals(orderId))).write(
      OrdersCompanion(
        status: Value(newStatus.name),
        updatedAt: Value(_clock()),
      ),
    );
    await _outbox.enqueue(
      id: _uuid(),
      forTable: 'orders',
      op: 'update',
      rowId: orderId,
      payload: {'id': orderId, 'status': newStatus.name, 'updated_at': _clock().toIso8601String()},
    );
  });
}
```

Constructor gains `OutboxRepository _outbox`, `DateTime Function() _clock`, `String Function() _uuid`. The Riverpod provider wires the real `appDatabaseProvider`, `outboxRepositoryProvider`, `DateTime.now`, and `() => const Uuid().v4()`.

Private helpers:
- `OrdersCompanion _toCompanion(LaundryOrder order, String actorStaffId)` — maps domain → row, sets `intakeRecordedBy` / `createdBy` on insert.
- `Map<String, dynamic> _toPayload(LaundryOrder order)` — JSON payload sent to Supabase.

### `ProofEventsRepository` write method

```dart
Future<void> insertEvent(ProofEvent event, {required String actorStaffId}) async {
  await _db.transaction(() async {
    final companion = _toCompanion(event, actorStaffId);
    await _db.into(_db.proofEvents).insert(companion);
    await _outbox.enqueue(
      id: _uuid(),
      forTable: 'proof_events',
      op: 'insert',
      rowId: event.id,                          // ProofEvent needs an id field if it doesn't have one yet
      payload: _toPayload(event),
    );
  });
}
```

If `ProofEvent` lacks an `id` field, add one (`final String id`) defaulted to `const Uuid().v4()` at construction time. Equality / hashCode update accordingly.

### `ordersStreamProvider` (`lib/src/sync/repository_providers.dart`)

```dart
final ordersStreamProvider = StreamProvider<List<LaundryOrder>>((ref) {
  final repo = ref.watch(ordersRepositoryProvider);
  return repo.watchAll();
});
```

(Reuses the existing `ordersRepositoryProvider`.)

### `OrdersSeeder` (`lib/src/data/orders_seeder.dart`)

```dart
class OrdersSeeder {
  OrdersSeeder({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;
  final DateTime Function() _clock;

  Future<void> seedIfEmpty(AppDatabase db) async {
    final existing = await (db.select(db.orders)..limit(1)).get();
    if (existing.isNotEmpty) return;
    await db.transaction(() async {
      await db.batch((batch) {
        batch.insertAll(db.orders, _fixtureOrders());
      });
    });
  }

  List<OrdersCompanion> _fixtureOrders();
}
```

`_fixtureOrders()` returns four `OrdersCompanion.insert(...)` rows, one per existing dashboard fixture (AMW-1024 Sarah N. / pendingPickup, AMW-1025 Brian K. / inProgress, AMW-1026 Grace A. / readyForDelivery, AMW-1027 Daniel M. / completed). The `id` is a hardcoded UUID per fixture (so re-runs don't insert duplicates and tests can assert against known ids); `orderCode` matches the existing "AMW-NNNN"; the other columns (`customerName`, `phone`, `address`, `serviceType`, `status`, `itemCount`, `notes`, `intakeMethod`, `fulfillmentMethod`, `intakeRecordedBy`, `createdBy`) come straight from the current `LaundryOrder` literals at [staff_dashboard_screen.dart:34-78](lib/src/dashboard/staff_dashboard_screen.dart#L34). `createdAt` / `updatedAt` default to `currentDateAndTime` from the schema. `scheduledFor`, `customerId`, `assignedDriver`, `deletedAt` stay null.

Hardcoded UUIDs (deterministic) so re-runs don't create duplicates and tests can rely on known ids.

### `app_bootstrap.dart` integration

After the `AppDatabase` is opened and before the UI starts, call:

```dart
await OrdersSeeder().seedIfEmpty(db);
```

Idempotent — safe to call on every startup.

### `StaffDashboardScreen` migration

- Class becomes `ConsumerStatefulWidget`. Generic state field gets `ConsumerState<StaffDashboardScreen>`.
- `_orders`, `_replaceUpdatedOrder`, and `_openOrderDetails`'s update-mutating tail all delete.
- `build` reads `final ordersAsync = ref.watch(ordersStreamProvider);` and switches on `.when(...)`:
  - `data:` — existing rendering, but iterates over `ordersAsync.value`.
  - `loading:` — render an empty `ListView` (visual parity with "no orders"); the empty state is brief.
  - `error:` — render a centered `Text("Could not load orders. Pull to retry.")` with a refresh button.
- Photo-recovery `retrieveLostPhoto` constructor param + `initState` SnackBar stay unchanged.

The action buttons (Notifications / New pickup / Check order / Report) and their `_ActionButton` row are unchanged.

### Capture screen migration

For each of `OrderDetailsScreen`, `PickupCaptureScreen`, `DeliveryCaptureScreen`:

1. Constructor gains `OrdersRepository ordersRepo` and (for the proof screens) `ProofEventsRepository proofEventsRepo`. Both required.
2. The build-`LaundryOrder`-and-pop logic in the action handler is replaced with:
   - For `PickupCaptureScreen` (`_onDone`): save photos → build `ProofEvent` → `await proofEventsRepo.insertEvent(...)` → `await ordersRepo.updateStatus(order.id, OrderStatus.inProgress, ...)` → `Navigator.pop<bool>(context, true)`.
   - For `DeliveryCaptureScreen` (`_markDelivered`): same shape with `OrderStatus.completed`.
   - For `OrderDetailsScreen` (the "Move to ..." button on `inProgress` orders): just `await ordersRepo.updateStatus(order.id, OrderStatus.readyForDelivery, ...)`. No proof event.
3. Existing try/catch error handling (Bug 2 fix) wraps the new writes. Catch path resets `_saving = false` and shows the existing SnackBar.
4. Existing `if (!mounted) return;` guards stay.
5. The dashboard's push site for each screen passes `ref.read(ordersRepositoryProvider)` and `ref.read(proofEventsRepositoryProvider)` into the screen constructors.

### Actor staff id

All write methods take `actorStaffId: String`. This populates `intakeRecordedBy` / `createdBy` on the orders row and `recordedBy` on proof events (per existing schema). The dashboard pulls it from `authServiceProvider.currentStaffId` (or equivalent) at the push site and passes it down.

If the auth layer doesn't yet expose a `currentStaffId`, the spec defers to whatever the existing `auth_service.dart` provides; if nothing usable exists, the plan task that wires this is allowed to add a small accessor.

## Testing

### New test files

- **`orders_repository_write_test.dart`** — pumps an in-memory `AppDatabase`, calls `upsertOrder(...)`, asserts: (a) the row exists with the right fields; (b) exactly one outbox row exists with `forTable: 'orders'`, `op: 'insert'`, matching `rowId` and JSON payload. Repeats for `updateStatus`.
- **`proof_events_repository_write_test.dart`** — analogous, asserts the proof_events row AND the outbox row.
- **`orders_stream_provider_test.dart`** — pumps a `ProviderContainer` with `appDatabaseProvider` overridden to an in-memory DB, listens to `ordersStreamProvider`, inserts a row via `OrdersRepository.upsertOrder`, asserts the stream emits with the new order.
- **`orders_seeder_test.dart`** — first call inserts 4 rows; second call is a no-op (existing rows untouched).

### Migrated test files

- **`staff_dashboard_screen_test.dart`** — wrap the `MaterialApp` with `ProviderScope(overrides: [appDatabaseProvider.overrideWithValue(testDb)])`; seed `testDb` with the desired orders directly before pumping. The two existing tests (lost-photo SnackBar, no-lost-photo) continue to assert their SnackBar behavior — they don't need to assert order rendering.
- **`pickup_capture_screen_test.dart`** — switch from "assert the popped `LaundryOrder` has updated status + proof event" to:
  - Inject an in-memory db + write through real `OrdersRepository` / `ProofEventsRepository` instances pointing at it.
  - After tapping Done + settling, query the db: `orders.status == 'inProgress'` and there's a matching `proof_events` row.
  - The existing "save fails → SnackBar + button re-enabled" test (Bug 2) keeps its shape, but the failure is injected via a `_ThrowingProofPhotoStorage` as today — the new repo write is gated behind photo save in `_onDone`, so it never runs.
- **`delivery_capture_screen_test.dart`** — analogous, target status `completed`.
- **`order_details_screen_test.dart`** — switch from asserting popped order to asserting the orders row's `status` changed for the `inProgress → readyForDelivery` button.

### Test infrastructure

A single helper `test/_support/in_memory_db.dart` exposes `AppDatabase newInMemoryDb()` that returns `AppDatabase(NativeDatabase.memory())` or equivalent. Reused across the new test files and the migrated ones. If a similar helper already exists on the branch, reuse it instead.

## Open Questions / Items the plan must resolve

1. **`ProofEvent` needs an `id` field.** If it doesn't have one, add it; UUIDs generated at construction. Update equality / hashCode / `copyWith` accordingly.
2. **`OrderStatus.name`** is the enum's canonical string for the `status` text column. If that doesn't match what `OrdersRepository.watchAll` reads back, a small `OrderStatus.fromName` round-trip helper may be needed (the migration task that touches this should verify).
3. **Pull-to-refresh / retry on stream error.** The dashboard's error state references "Pull to retry." Whether to wire `RefreshIndicator` or just a tap-to-retry button is a UI judgment the plan can settle.

## Migration risk & rollback

- **Risk:** a regression in any capture screen leaves an order's status out of sync between Drift (updated) and the popped `LaundryOrder` (stale). Mitigation: the spec removes the popped `LaundryOrder` from the API entirely — there's no stale value to leak.
- **Risk:** a Drift exception during write surfaces only as a SnackBar; the rider thinks the operation failed and retries, double-writing. Mitigation: write methods use `insertOnConflictUpdate` (idempotent on the row) and outbox enqueue uses `InsertMode.insertOrIgnore` with deterministic ids — a retry is a no-op.
- **Rollback:** revert the migration commits; the dashboard reverts to the in-memory list. No data loss because seed data lives in the local Drift DB and is harmless.

## Out of scope (deferred — call out so PR-B knows)

- New Pickup form (PR-B).
- Customer dedup by phone (PR-B).
- GPS pre-fill (PR-B).
- Schedule-for-later UI (PR-B; the `scheduledFor` column already exists).
- Converting capture screens to `ConsumerWidget` (future cleanup).
- Pull-to-refresh wiring beyond the minimum error-state retry.
- Outbox dead-letter UI surface.
- Migrating fixture orders to Supabase (intentionally local-only).
