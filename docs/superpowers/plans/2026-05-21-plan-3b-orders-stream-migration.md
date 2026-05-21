# Plan 3b — Orders-Stream Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the parallel-truth gap on the staff dashboard — dashboard reads orders from Drift via `OrdersRepository.watchAll()`, and the three proof-capture screens write to Drift + outbox before popping. Unblocks PR-B (New Pickup form).

**Architecture:** Plan 3a built the read-side rails (repositories, providers, orchestrator) but no screen consumes them yet. Plan 3b adds the write-side (`upsertOrder`, `updateStatus`, `insertEvent`), a `StreamProvider<List<LaundryOrder>>`, a first-launch seeder, and swaps `StaffDashboardScreen` to read the stream. Capture screens stay `StatefulWidget` but gain constructor-injected repos and write before popping.

**Tech Stack:** Dart 3.8, Flutter, Drift 2.x, supabase_flutter 2.x, flutter_riverpod 2.5, mocktail. Adds the `uuid` package for mutation-id generation.

**Source spec:** [docs/superpowers/specs/2026-05-18-orders-stream-migration-design.md](../specs/2026-05-18-orders-stream-migration-design.md)
**Prerequisite plan:** [2026-05-19-plan-3a-sync-foundation.md](2026-05-19-plan-3a-sync-foundation.md) (merged).

---

## Context

Plan 3a built repositories, Riverpod providers, the SyncOrchestrator + auth lifecycle, and mounted the `SyncStatusBanner` — but **no UI screen reads from or writes through any of it**. The dashboard still renders a hardcoded `final List<LaundryOrder> _orders = [...]` literal and mutates it via `setState`; the three proof-capture screens build an updated `LaundryOrder` and return it through `Navigator.pop`, which the dashboard then swaps into its in-memory list.

That parallel-truth setup blocks every feature on top of the new sync layer — writes land in `setState` while reads come from Drift, so the screens diverge. PR-B (the New Pickup form, the actual product feature this enables) can't be built until this closes.

Plan 3b's outcome: dashboard reads orders from `OrdersRepository.watchAll()` via a `StreamProvider`, the three capture screens write through `OrdersRepository` + `ProofEventsRepository` (which enqueue outbox rows in the same DB transaction as the Drift write), and a first-launch seeder populates the four demo orders so manual testing has data on day one. **No** sync to Supabase changes — the outbox + worker from Plan 2 picks up writes automatically.

## Locked-in decisions (carried from the spec)

- **Dashboard only converts to `ConsumerStatefulWidget`.** Capture screens stay `StatefulWidget` with constructor injection (smallest migration that closes the gap).
- **Capture screens write to Drift before popping.** The pop now signals "done navigating," not "here's the new data." Each screen pops `bool` (success) or nothing.
- **Seed orders are local-only.** No outbox enqueue for the seeded fixtures — each rider's local DB is independently seeded; production Supabase isn't polluted.
- **Writes are atomic per logical change.** `OrdersRepository.upsertOrder`, `updateStatus`, and `ProofEventsRepository.insertEvent` each wrap their Drift mutation + outbox enqueue in one `db.transaction`. A crash mid-write leaves the local row and the outbox row consistent.
- **`LaundryOrder` stays as the domain model.** `LaundryOrder.fromDriftRow(row, events)` (Plan 3a Task 1) is the only adapter.
- **`auth.uid() = staff.id`.** Supabase migration 0007 makes the auth user id and the staff row id identical, so the existing `currentUserIdProvider` (lib/src/auth/session.dart:12) is the actor staff id. No new provider needed.

## Architecture

```
StaffDashboardScreen (ConsumerStatefulWidget)
  └── ref.watch(ordersStreamProvider).when(
        data:  -> existing render over List<LaundryOrder>
        loading: -> empty ListView (visual parity with "no orders")
        error:   -> retry SnackBar + centered message
      )

ordersStreamProvider = StreamProvider<List<LaundryOrder>>
  └── repo.watchAll()   (Plan 3a OrdersRepository — unchanged read path)

PickupCaptureScreen._onDone:
  save photos → build ProofEvent → await proofEventsRepo.insertEvent(...)
              → await ordersRepo.updateStatus(order.id, OrderStatus.inProgress, actorStaffId)
              → Navigator.pop<bool>(context, true)

DeliveryCaptureScreen._markDelivered:    same shape; target status = completed
OrderDetailsScreen "Move to..." button:  just ordersRepo.updateStatus(..., readyForDelivery, ...)

AppBootstrap.initialize:
  Supabase.initialize(...) → OrdersSeeder().seedIfEmpty(db)
```

## Resolved open questions from the spec

| Spec OQ | Resolution |
|---|---|
| **#1 ProofEvent needs an `id`** | Task 1 adds `final String id` to `ProofEvent` (default: caller-supplied via `Uuid().v4()`). `LaundryOrder.fromDriftRow` (Plan 3a Task 1) is updated to plumb the Drift row's `id` into the domain `ProofEvent`. |
| **#2 OrderStatus.name vs DB status text** | Task 2 adds `OrderStatus.toDbString` — returns `pending_pickup` / `in_progress` / `ready` / `completed` (NOT enum.name's `pendingPickup`/etc.). Round-trips with Plan 3a's `_statusFromString` in `LaundryOrder.fromDriftRow`. |
| **#3 Pull-to-refresh on stream error** | Settled inside Task 9: tap-to-retry button + a SnackBar. Full `RefreshIndicator` is deferred (the puller's 15s tick + connectivity-edge already provides natural refresh). |

## File Layout

```
lib/src/
├── orders/
│   ├── proof_event.dart                       [modify — add id field]
│   ├── order_status.dart                      [modify — add toDbString]
│   └── order.dart                             [modify — fromDriftRow plumbs ProofEvent.id]
├── sync/
│   ├── outbox_repository.dart                 [unchanged — Plan 2]
│   ├── orders_repository.dart                 [modify — add upsertOrder + updateStatus + deps]
│   ├── proof_events_repository.dart           [modify — add insertEvent + deps]
│   └── repository_providers.dart              [modify — outboxRepositoryProvider, ordersStreamProvider, plus wire new deps into orders/proof_events providers]
├── data/
│   └── orders_seeder.dart                     [new]
├── bootstrap/
│   └── app_bootstrap.dart                     [modify — call OrdersSeeder.seedIfEmpty after Supabase.initialize]
├── dashboard/
│   └── staff_dashboard_screen.dart            [modify — ConsumerStatefulWidget reading ordersStreamProvider]
└── orders/
    ├── order_details_screen.dart              [modify — accept OrdersRepository, write status before pop]
    └── proof/
        ├── pickup_capture_screen.dart         [modify — accept both repos, write before pop]
        └── delivery_capture_screen.dart       [modify — same as pickup]

test/
├── orders/
│   ├── proof_event_test.dart                  [modify — assert id roundtrip]
│   ├── order_status_test.dart                 [modify — assert toDbString round-trip]
│   ├── order_from_drift_row_test.dart         [modify — assert ProofEvent.id is plumbed]
│   ├── order_details_screen_test.dart         [modify — assert DB row changed, not popped order]
│   └── proof/
│       ├── pickup_capture_screen_test.dart    [modify — assert DB row + outbox row, not popped order]
│       └── delivery_capture_screen_test.dart  [modify — same]
├── sync/
│   ├── outbox_repository_provider_test.dart   [new]
│   ├── orders_repository_write_test.dart      [new]
│   ├── proof_events_repository_write_test.dart [new]
│   ├── orders_stream_provider_test.dart       [new]
│   └── repository_providers_test.dart         [modify — add outboxRepositoryProvider + ordersStreamProvider singleton assertions]
├── data/
│   └── orders_seeder_test.dart                [new]
└── dashboard/
    └── staff_dashboard_screen_test.dart       [modify — pump with ProviderScope + in-memory DB; seed via OrdersRepository]

pubspec.yaml                                   [modify — add uuid: ^4.5.0]
```

Reuse: `OutboxRepository` (lib/src/sync/outbox_repository.dart), `OutboxRepository.enqueue`, `currentUserIdProvider` (lib/src/auth/session.dart:12), `appDatabaseProvider`, `LaundryOrder.fromDriftRow` (Plan 3a Task 1), `OrdersRepository.watchAll` (Plan 3a Task 2) — all unchanged in shape.

---

## Task list

Each task = one commit. TDD: red test first, then implementation, then verification. Use scoped `git commit -- <paths>` per existing memory rule. Run `flutter test <path>` one file at a time (per saved memory — multi-path invocations hang on this Windows host).

### Task 1: Add `id` field to `ProofEvent` domain class

Resolves spec Open Question #1. Without an `id`, `ProofEventsRepository.insertEvent` (Task 5) can't enqueue an outbox row keyed by the proof-event row id.

**Files:**
- Modify: `lib/src/orders/proof_event.dart`
- Modify: `lib/src/orders/order.dart` (fromDriftRow plumbs the Drift row's `id` into the domain `ProofEvent`)
- Modify: `test/orders/proof_event_test.dart` (assert id field equality)
- Modify: `test/orders/order_from_drift_row_test.dart` (assert mapped ProofEvent carries the Drift row id)

- [ ] **Step 1: Failing tests**

In `test/orders/proof_event_test.dart`, add:
```dart
test('id is part of equality + hashCode', () {
  final a = ProofEvent(
    id: 'pe-1',
    type: ProofEventType.pickup,
    capturedAt: DateTime.utc(2026, 5, 21, 10),
    count: 3,
    photoPaths: const [],
  );
  final b = ProofEvent(
    id: 'pe-2',
    type: ProofEventType.pickup,
    capturedAt: DateTime.utc(2026, 5, 21, 10),
    count: 3,
    photoPaths: const [],
  );
  expect(a, isNot(b));
  expect(a.hashCode, isNot(b.hashCode));
});
```

In `test/orders/order_from_drift_row_test.dart`, extend the "maps two proof events" test:
```dart
expect(mapped.proofEvents[0].id, 'pe-1');
expect(mapped.proofEvents[1].id, 'pe-2');
```

- [ ] **Step 2: Run tests, confirm RED**

`flutter test test/orders/proof_event_test.dart` — compile error (no `id` parameter).
`flutter test test/orders/order_from_drift_row_test.dart` — assertion fail.

- [ ] **Step 3: Implementation**

In `lib/src/orders/proof_event.dart`:
```dart
class ProofEvent {
  const ProofEvent({
    required this.id,
    required this.type,
    required this.capturedAt,
    required this.count,
    required this.photoPaths,
    this.notes,
  });

  final String id;
  final ProofEventType type;
  // ...rest unchanged...
}
```

Update `operator ==` to compare `id`; update `hashCode` to include `id`.

In `lib/src/orders/order.dart`, inside the `LaundryOrder.fromDriftRow` factory's `events.map((e) => ProofEvent(...))`:
```dart
ProofEvent(
  id: e.id,        // NEW — Drift row id flows through
  type: _proofTypeFromString(e.type),
  capturedAt: e.capturedAt,
  count: e.itemCount,
  photoPaths: const [],
  notes: e.notes,
),
```

- [ ] **Step 4: Update all existing `ProofEvent` construction sites**

Add `id: 'pe-...'` (or a `Uuid().v4()` if construction is dynamic) at every existing `ProofEvent(...)` call site outside the mapper. Grep first:

`grep -rn "ProofEvent(" lib test --include="*.dart"`

Notable call sites (from current code): `lib/src/orders/proof/pickup_capture_screen.dart` `_onDone`, `lib/src/orders/proof/delivery_capture_screen.dart` `_markDelivered`. Use a fresh `Uuid().v4()` for those (uuid dep arrives in Task 3 — temporarily use `'pe-${DateTime.now().microsecondsSinceEpoch}'` here and switch to proper UUIDs in Task 11/12 when the capture screens are rewritten anyway).

- [ ] **Step 5: Run tests, confirm GREEN**

`flutter test test/orders/proof_event_test.dart`
`flutter test test/orders/order_from_drift_row_test.dart`
Both green.

- [ ] **Step 6: Analyze + commit**

```bash
flutter analyze lib/src/orders/proof_event.dart lib/src/orders/order.dart test/orders/proof_event_test.dart test/orders/order_from_drift_row_test.dart
# Expect: No issues found
git add lib/src/orders/proof_event.dart lib/src/orders/order.dart test/orders/proof_event_test.dart test/orders/order_from_drift_row_test.dart <any updated call-site files>
git commit -m "Add id field to ProofEvent domain class"
```

### Task 2: Add `OrderStatus.toDbString` round-trip helper

Resolves spec Open Question #2. `OrderStatus.name` returns camelCase (`'inProgress'`) but the DB stores Postgres-style `snake_case` (`'in_progress'`). Write-path needs an explicit `toDbString` that round-trips with Plan 3a's `_statusFromString`.

**Files:**
- Modify: `lib/src/orders/order_status.dart`
- Modify: `test/orders/order_status_test.dart`

- [ ] **Step 1: Failing test**

In `test/orders/order_status_test.dart`:
```dart
import 'package:amuwak_staff/src/orders/order.dart';
// ...

test('toDbString returns the Postgres canonical name', () {
  expect(OrderStatus.pendingPickup.toDbString(), 'pending_pickup');
  expect(OrderStatus.inProgress.toDbString(), 'in_progress');
  expect(OrderStatus.readyForDelivery.toDbString(), 'ready');
  expect(OrderStatus.completed.toDbString(), 'completed');
});

test('toDbString round-trips through LaundryOrder.fromDriftRow', () {
  for (final s in OrderStatus.values) {
    // Build a Drift Order row with this status's DB string, run it through
    // the mapper, expect the same enum back. Construction helper from
    // order_from_drift_row_test reused inline.
    // ...assertion shape: fromDriftRow(_orderRow(status: s.toDbString()), []).status == s
  }
});
```

(The second test mirrors the helper from `order_from_drift_row_test.dart` — copy the `_orderRow` builder or refactor it into a shared `test/_support/order_fixtures.dart` while you're here.)

- [ ] **Step 2: Run, confirm RED** (`toDbString` undefined).

- [ ] **Step 3: Implementation**

In `lib/src/orders/order_status.dart`:
```dart
enum OrderStatus {
  pendingPickup(label: 'Pending pickup', color: Color(0xFF9A5B00)),
  inProgress(label: 'In progress', color: Color(0xFF7A4CC2)),
  readyForDelivery(label: 'Ready for delivery', color: Color(0xFF0B7285)),
  completed(label: 'Completed', color: Color(0xFF2F7D32));

  const OrderStatus({required this.label, required this.color});
  final String label;
  final Color color;

  String toDbString() => switch (this) {
    OrderStatus.pendingPickup    => 'pending_pickup',
    OrderStatus.inProgress       => 'in_progress',
    OrderStatus.readyForDelivery => 'ready',
    OrderStatus.completed        => 'completed',
  };

  OrderStatus? get nextStatus => /* unchanged */;
}
```

- [ ] **Step 4: Run, confirm GREEN**.

- [ ] **Step 5: Analyze + commit**

```bash
git add lib/src/orders/order_status.dart test/orders/order_status_test.dart
git commit -m "Add OrderStatus.toDbString round-trip helper"
```

### Task 3: Add `uuid` dependency + `outboxRepositoryProvider`

Plan 3a created repository providers for the five **read** repos but missed an `outboxRepositoryProvider`. Tasks 4 and 5 need it. Also: add the `uuid` package because outbox enqueues need unique mutation ids.

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/src/sync/repository_providers.dart`
- Modify: `test/sync/repository_providers_test.dart` (add outboxRepositoryProvider singleton assertion)

- [ ] **Step 1: Add uuid to pubspec.yaml**

Under `dependencies:`:
```yaml
uuid: ^4.5.0
```

Run `flutter pub get`.

- [ ] **Step 2: Failing test** in `test/sync/repository_providers_test.dart`:

```dart
test('outboxRepositoryProvider resolves to an OutboxRepository singleton', () {
  final a = container.read(outboxRepositoryProvider);
  final b = container.read(outboxRepositoryProvider);
  expect(a, isA<OutboxRepository>());
  expect(identical(a, b), isTrue);
});
```

- [ ] **Step 3: Run, confirm RED**.

- [ ] **Step 4: Implementation** in `lib/src/sync/repository_providers.dart`:

Add the import:
```dart
import 'outbox_repository.dart';
```

Add the provider (placed near the other repo providers):
```dart
final outboxRepositoryProvider = Provider<OutboxRepository>(
  (ref) => OutboxRepository(ref.watch(appDatabaseProvider)),
);
```

- [ ] **Step 5: Run, confirm GREEN**.

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/src/sync/repository_providers.dart test/sync/repository_providers_test.dart
git commit -m "Add uuid dep and outboxRepositoryProvider"
```

### Task 4: `OrdersRepository` write methods

Add `upsertOrder` and `updateStatus`. Each runs in a single `db.transaction` so the local row and the outbox row commit (or roll back) together.

**Files:**
- Modify: `lib/src/sync/orders_repository.dart`
- Modify: `lib/src/sync/repository_providers.dart` (rewire `ordersRepositoryProvider` for new deps)
- Create: `test/sync/orders_repository_write_test.dart`

- [ ] **Step 1: Failing tests** in `test/sync/orders_repository_write_test.dart`:

```dart
import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:amuwak_staff/src/data/app_database.dart';
import 'package:amuwak_staff/src/orders/order.dart';
import 'package:amuwak_staff/src/orders/order_status.dart';
import 'package:amuwak_staff/src/sync/orders_repository.dart';
import 'package:amuwak_staff/src/sync/outbox_repository.dart';

void main() {
  late AppDatabase db;
  late OutboxRepository outbox;
  late OrdersRepository repo;
  final clock = () => DateTime.utc(2026, 5, 21, 12, 0);
  var nextId = 0;
  final uuid = () => 'mut-${++nextId}';

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    outbox = OutboxRepository(db);
    repo = OrdersRepository(db, outbox: outbox, clock: clock, uuid: uuid);
    nextId = 0;
  });
  tearDown(() async => db.close());

  group('upsertOrder', () {
    test('writes the row and enqueues exactly one outbox insert', () async {
      const order = LaundryOrder(
        orderId: 'AMW-A',
        customerName: 'Sarah',
        serviceType: 'wash',
        status: OrderStatus.pendingPickup,
        timeLabel: '10:00 AM',
        itemCount: 3,
        phone: '+256',
        address: 'addr',
        notes: '',
      );

      await repo.upsertOrder(order, actorStaffId: 's-1');

      final row = await (db.select(db.orders)..where((t) => t.id.equals('AMW-A'))).getSingle();
      expect(row.status, 'pending_pickup');
      expect(row.customerName, 'Sarah');
      expect(row.intakeRecordedBy, 's-1');
      expect(row.createdBy, 's-1');

      final outboxRows = await db.select(db.outbox).get();
      expect(outboxRows, hasLength(1));
      expect(outboxRows.single.forTable, 'orders');
      expect(outboxRows.single.op, 'insert');
      expect(outboxRows.single.rowId, 'AMW-A');
      final payload = jsonDecode(outboxRows.single.payloadJson) as Map;
      expect(payload['id'], 'AMW-A');
      expect(payload['status'], 'pending_pickup');
    });

    test('a Drift exception rolls back the outbox enqueue', () async {
      // Insert a row, then upsertOrder with the same id but a payload that
      // throws during _toCompanion (or just force the transaction to
      // fail by closing the db mid-call). Cleanest: stub _toPayload? Not
      // worth it — verify the happy-path atomicity instead.
      // Skipped — the transaction guarantee is Drift's, not ours.
    }, skip: 'transaction atomicity is provided by Drift; not unit-testable without invasive seams');
  });

  group('updateStatus', () {
    test('updates the row\'s status + updated_at and enqueues an outbox update', () async {
      // Seed an order
      await db.into(db.orders).insert(OrdersCompanion.insert(
        id: 'AMW-A',
        orderCode: 'AMW-A',
        customerName: 'Sarah',
        phone: '+256', address: 'addr', serviceType: 'wash',
        status: 'in_progress',
        intakeMethod: 'driver_pickup', fulfillmentMethod: 'delivery',
        itemCount: 3,
        intakeRecordedBy: 's-1', createdBy: 's-1',
      ));

      await repo.updateStatus('AMW-A', OrderStatus.readyForDelivery, actorStaffId: 's-1');

      final row = await (db.select(db.orders)..where((t) => t.id.equals('AMW-A'))).getSingle();
      expect(row.status, 'ready');
      expect(row.updatedAt.toUtc(), DateTime.utc(2026, 5, 21, 12, 0));

      final outboxRows = await db.select(db.outbox).get();
      expect(outboxRows, hasLength(1));
      expect(outboxRows.single.op, 'update');
      expect(outboxRows.single.rowId, 'AMW-A');
      final payload = jsonDecode(outboxRows.single.payloadJson) as Map;
      expect(payload['status'], 'ready');
      expect(payload['updated_at'], '2026-05-21T12:00:00.000Z');
    });
  });
}
```

- [ ] **Step 2: Run, confirm RED** — `OrdersRepository` constructor doesn't accept `outbox/clock/uuid` and methods don't exist.

- [ ] **Step 3: Implementation** in `lib/src/sync/orders_repository.dart`:

```dart
import 'package:drift/drift.dart' show Value;

import '../data/app_database.dart';
import '../orders/order.dart';
import '../orders/order_status.dart';
import 'outbox_repository.dart';

class OrdersRepository {
  OrdersRepository(
    this._db, {
    OutboxRepository? outbox,
    DateTime Function()? clock,
    String Function()? uuid,
  })  : _outbox = outbox,
        _clock = clock ?? DateTime.now,
        _uuid = uuid ?? _defaultUuid;

  final AppDatabase _db;
  final OutboxRepository? _outbox;
  final DateTime Function() _clock;
  final String Function() _uuid;

  static String _defaultUuid() => const Uuid().v4(); // import 'package:uuid/uuid.dart';

  // ----- READ (unchanged from Plan 3a) -----
  Stream<List<LaundryOrder>> watchAll() { /* existing */ }
  Stream<LaundryOrder?> watchById(String orderId) { /* existing */ }

  // ----- WRITE (new) -----
  Future<void> upsertOrder(LaundryOrder order, {required String actorStaffId}) async {
    final outbox = _requireOutbox();
    await _db.transaction(() async {
      await _db.into(_db.orders).insertOnConflictUpdate(
        _toCompanion(order, actorStaffId, now: _clock()),
      );
      await outbox.enqueue(
        id: _uuid(),
        forTable: 'orders',
        op: 'insert',
        rowId: order.orderId,
        payload: _toPayload(order, actorStaffId, now: _clock()),
      );
    });
  }

  Future<void> updateStatus(String orderId, OrderStatus newStatus,
      {required String actorStaffId}) async {
    final outbox = _requireOutbox();
    final now = _clock();
    final dbStatus = newStatus.toDbString();
    await _db.transaction(() async {
      await (_db.update(_db.orders)..where((t) => t.id.equals(orderId))).write(
        OrdersCompanion(status: Value(dbStatus), updatedAt: Value(now)),
      );
      await outbox.enqueue(
        id: _uuid(),
        forTable: 'orders',
        op: 'update',
        rowId: orderId,
        payload: <String, dynamic>{
          'id': orderId,
          'status': dbStatus,
          'updated_at': now.toUtc().toIso8601String(),
        },
      );
    });
  }

  OutboxRepository _requireOutbox() {
    final o = _outbox;
    if (o == null) {
      throw StateError('OrdersRepository was constructed without an OutboxRepository; '
          'write methods are unavailable.');
    }
    return o;
  }

  OrdersCompanion _toCompanion(LaundryOrder order, String actorStaffId,
      {required DateTime now}) {
    return OrdersCompanion(
      id: Value(order.orderId),
      orderCode: Value(order.orderId),
      customerName: Value(order.customerName),
      phone: Value(order.phone),
      address: Value(order.address),
      serviceType: Value(order.serviceType),
      status: Value(order.status.toDbString()),
      // Default values — capture flow fills these in via the form
      intakeMethod: const Value('driver_pickup'),
      fulfillmentMethod: const Value('delivery'),
      itemCount: Value(order.itemCount),
      notes: Value(order.notes),
      intakeRecordedBy: Value(actorStaffId),
      createdBy: Value(actorStaffId),
      createdAt: Value(now),
      updatedAt: Value(now),
    );
  }

  Map<String, dynamic> _toPayload(LaundryOrder order, String actorStaffId,
      {required DateTime now}) => {
        'id': order.orderId,
        'order_code': order.orderId,
        'customer_name': order.customerName,
        'phone': order.phone,
        'address': order.address,
        'service_type': order.serviceType,
        'status': order.status.toDbString(),
        'intake_method': 'driver_pickup',
        'fulfillment_method': 'delivery',
        'item_count': order.itemCount,
        'notes': order.notes,
        'intake_recorded_by': actorStaffId,
        'created_by': actorStaffId,
        'created_at': now.toUtc().toIso8601String(),
        'updated_at': now.toUtc().toIso8601String(),
      };
}
```

- [ ] **Step 4: Rewire `ordersRepositoryProvider`** in `lib/src/sync/repository_providers.dart`:

```dart
final ordersRepositoryProvider = Provider<OrdersRepository>(
  (ref) => OrdersRepository(
    ref.watch(appDatabaseProvider),
    outbox: ref.watch(outboxRepositoryProvider),
  ),
);
```

(Defaults for `clock`/`uuid` keep production wiring trivial; tests override the whole provider with their own stubs.)

- [ ] **Step 5: Run, confirm GREEN**.

- [ ] **Step 6: Commit**

```bash
git add lib/src/sync/orders_repository.dart lib/src/sync/repository_providers.dart test/sync/orders_repository_write_test.dart
git commit -m "Add OrdersRepository.upsertOrder and updateStatus"
```

### Task 5: `ProofEventsRepository.insertEvent`

Same pattern as Task 4. Writes a `proof_events` row and an outbox `insert` row in one transaction.

**Files:**
- Modify: `lib/src/sync/proof_events_repository.dart`
- Modify: `lib/src/sync/repository_providers.dart`
- Create: `test/sync/proof_events_repository_write_test.dart`

- [ ] **Step 1: Failing test** in `test/sync/proof_events_repository_write_test.dart`:

```dart
test('insertEvent writes the row and enqueues an outbox insert', () async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  final outbox = OutboxRepository(db);
  final repo = ProofEventsRepository(db,
    outbox: outbox,
    clock: () => DateTime.utc(2026, 5, 21, 12),
    uuid: () => 'mut-1',
  );

  final event = ProofEvent(
    id: 'pe-1',
    type: ProofEventType.pickup,
    capturedAt: DateTime.utc(2026, 5, 21, 10, 30),
    count: 3,
    photoPaths: const [],
    notes: 'Bagged carefully',
  );

  await repo.insertEvent(event, orderId: 'AMW-A', actorStaffId: 's-1');

  final rows = await db.select(db.proofEvents).get();
  expect(rows.single.id, 'pe-1');
  expect(rows.single.orderId, 'AMW-A');
  expect(rows.single.type, 'pickup');
  expect(rows.single.capturedBy, 's-1');
  expect(rows.single.itemCount, 3);

  final outboxRows = await db.select(db.outbox).get();
  expect(outboxRows.single.forTable, 'proof_events');
  expect(outboxRows.single.op, 'insert');
  expect(outboxRows.single.rowId, 'pe-1');
  final payload = jsonDecode(outboxRows.single.payloadJson) as Map;
  expect(payload['type'], 'pickup');
  expect(payload['captured_by'], 's-1');

  await db.close();
});
```

- [ ] **Step 2: Confirm RED**.

- [ ] **Step 3: Implementation** in `lib/src/sync/proof_events_repository.dart`:

```dart
import 'package:drift/drift.dart' hide JsonKey;

import '../data/app_database.dart';
import '../orders/proof_event.dart';
import 'outbox_repository.dart';

class ProofEventsRepository {
  ProofEventsRepository(
    this._db, {
    OutboxRepository? outbox,
    DateTime Function()? clock,
    String Function()? uuid,
  })  : _outbox = outbox,
        _clock = clock ?? DateTime.now,
        _uuid = uuid ?? _defaultUuid;

  final AppDatabase _db;
  final OutboxRepository? _outbox;
  final DateTime Function() _clock;
  final String Function() _uuid;

  static String _defaultUuid() => const Uuid().v4();

  Stream<List<ProofEvent>> watchByOrder(String orderId) { /* existing Plan 3a */ }

  Future<void> insertEvent(
    ProofEvent event, {
    required String orderId,
    required String actorStaffId,
  }) async {
    final outbox = _outbox;
    if (outbox == null) {
      throw StateError('ProofEventsRepository constructed without an OutboxRepository.');
    }
    final now = _clock();
    await _db.transaction(() async {
      await _db.into(_db.proofEvents).insert(
        ProofEventsCompanion.insert(
          id: event.id,
          orderId: orderId,
          type: event.type.name,           // 'pickup' | 'delivery' — already canonical
          capturedAt: event.capturedAt,
          itemCount: event.count,
          notes: Value(event.notes),
          capturedBy: actorStaffId,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await outbox.enqueue(
        id: _uuid(),
        forTable: 'proof_events',
        op: 'insert',
        rowId: event.id,
        payload: <String, dynamic>{
          'id': event.id,
          'order_id': orderId,
          'type': event.type.name,
          'captured_at': event.capturedAt.toUtc().toIso8601String(),
          'item_count': event.count,
          'notes': event.notes,
          'captured_by': actorStaffId,
          'created_at': now.toUtc().toIso8601String(),
          'updated_at': now.toUtc().toIso8601String(),
        },
      );
    });
  }
}
```

Wait — `ProofEvent.watchByOrder` returns Drift `ProofEvent`, but if we import `proof_event.dart` here we get a name collision. Use an import alias:
```dart
import '../data/app_database.dart' as drift;
// Type the existing read methods as Stream<List<drift.ProofEvent>>.
```

Rewire `proofEventsRepositoryProvider`:
```dart
final proofEventsRepositoryProvider = Provider<ProofEventsRepository>(
  (ref) => ProofEventsRepository(
    ref.watch(appDatabaseProvider),
    outbox: ref.watch(outboxRepositoryProvider),
  ),
);
```

- [ ] **Step 4: Confirm GREEN**.

- [ ] **Step 5: Commit**

```bash
git add lib/src/sync/proof_events_repository.dart lib/src/sync/repository_providers.dart test/sync/proof_events_repository_write_test.dart
git commit -m "Add ProofEventsRepository.insertEvent"
```

### Task 6: `ordersStreamProvider`

A thin `StreamProvider<List<LaundryOrder>>` wrapping `ordersRepositoryProvider.watchAll()` so the dashboard can `ref.watch(ordersStreamProvider).when(...)`.

**Files:**
- Modify: `lib/src/sync/repository_providers.dart`
- Create: `test/sync/orders_stream_provider_test.dart`

- [ ] **Step 1: Failing test** in `test/sync/orders_stream_provider_test.dart`:

```dart
test('ordersStreamProvider emits orders inserted through OrdersRepository', () async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  final container = ProviderContainer(overrides: [
    appDatabaseProvider.overrideWithValue(db),
  ]);

  // Initial emission — empty.
  final firstFrame = await container.read(ordersStreamProvider.future);
  expect(firstFrame, isEmpty);

  // Insert through the repo write path.
  await container.read(ordersRepositoryProvider).upsertOrder(
    const LaundryOrder(
      orderId: 'AMW-A',
      customerName: 'Sarah',
      serviceType: 'wash',
      status: OrderStatus.pendingPickup,
      timeLabel: '10:00 AM',
      itemCount: 3,
      phone: '+256', address: 'addr', notes: '',
    ),
    actorStaffId: 's-1',
  );

  // Stream emits the new order.
  await Future<void>.delayed(const Duration(milliseconds: 30));
  final next = container.read(ordersStreamProvider).valueOrNull;
  expect(next, isNotNull);
  expect(next!.single.orderId, 'AMW-A');

  container.dispose();
  await db.close();
});
```

- [ ] **Step 2: Confirm RED** (`ordersStreamProvider` undefined).

- [ ] **Step 3: Implementation** in `lib/src/sync/repository_providers.dart`:

```dart
final ordersStreamProvider = StreamProvider<List<LaundryOrder>>(
  (ref) => ref.watch(ordersRepositoryProvider).watchAll(),
);
```

- [ ] **Step 4: Confirm GREEN**.

- [ ] **Step 5: Commit**

```bash
git add lib/src/sync/repository_providers.dart test/sync/orders_stream_provider_test.dart
git commit -m "Add ordersStreamProvider for the dashboard read path"
```

### Task 7: `OrdersSeeder`

First-launch seed of the four demo orders so the dashboard isn't empty on day one. Local-only — no outbox enqueue.

**Files:**
- Create: `lib/src/data/orders_seeder.dart`
- Create: `test/data/orders_seeder_test.dart`

- [ ] **Step 1: Failing test** in `test/data/orders_seeder_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:amuwak_staff/src/data/app_database.dart';
import 'package:amuwak_staff/src/data/orders_seeder.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  test('seedIfEmpty inserts the four demo orders on first run', () async {
    final seeder = OrdersSeeder(clock: () => DateTime.utc(2026, 5, 21, 8));
    await seeder.seedIfEmpty(db);

    final rows = await db.select(db.orders).get();
    expect(rows, hasLength(4));
    expect(rows.map((r) => r.orderCode).toSet(),
        {'AMW-1024', 'AMW-1025', 'AMW-1026', 'AMW-1027'});
  });

  test('seedIfEmpty is a no-op when the table already has rows', () async {
    final seeder = OrdersSeeder(clock: () => DateTime.utc(2026, 5, 21, 8));
    await seeder.seedIfEmpty(db);
    await seeder.seedIfEmpty(db);

    final rows = await db.select(db.orders).get();
    expect(rows, hasLength(4));
  });

  test('seedIfEmpty writes no outbox rows (seed is local-only)', () async {
    final seeder = OrdersSeeder(clock: () => DateTime.utc(2026, 5, 21, 8));
    await seeder.seedIfEmpty(db);

    final outboxRows = await db.select(db.outbox).get();
    expect(outboxRows, isEmpty);
  });
}
```

- [ ] **Step 2: Confirm RED**.

- [ ] **Step 3: Implementation** in `lib/src/data/orders_seeder.dart`:

```dart
import 'package:drift/drift.dart' show Value;
import 'app_database.dart';

class OrdersSeeder {
  OrdersSeeder({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;
  final DateTime Function() _clock;

  Future<void> seedIfEmpty(AppDatabase db) async {
    final existing = await (db.select(db.orders)..limit(1)).get();
    if (existing.isNotEmpty) return;
    final now = _clock();
    await db.batch((batch) {
      batch.insertAll(db.orders, _fixtureOrders(now));
    });
  }

  // Deterministic hardcoded ids so re-runs don't duplicate and tests can rely
  // on them. Mirrors the four LaundryOrder literals currently at
  // lib/src/dashboard/staff_dashboard_screen.dart:34-78.
  List<OrdersCompanion> _fixtureOrders(DateTime now) => [
    OrdersCompanion.insert(
      id: '00000000-0000-4000-8000-0000AAA01024',
      orderCode: 'AMW-1024',
      customerName: 'Sarah N.',
      phone: '+256 700 123 456',
      address: 'Kikoni, near Makerere western gate',
      serviceType: 'Wash & Iron',
      status: 'pending_pickup',
      intakeMethod: 'driver_pickup',
      fulfillmentMethod: 'delivery',
      itemCount: 8,
      notes: const Value('Customer requested careful handling for white shirts.'),
      intakeRecordedBy: '00000000-0000-4000-8000-000000000001',
      createdBy: '00000000-0000-4000-8000-000000000001',
      createdAt: Value(now),
      updatedAt: Value(now),
    ),
    OrdersCompanion.insert(
      id: '00000000-0000-4000-8000-0000AAA01025',
      orderCode: 'AMW-1025',
      customerName: 'Brian K.',
      phone: '+256 701 456 789',
      address: 'Wandegeya, opposite main stage',
      serviceType: 'Dry cleaning',
      status: 'in_progress',
      intakeMethod: 'driver_pickup',
      fulfillmentMethod: 'delivery',
      itemCount: 3,
      notes: const Value('Suit jacket and trousers. Keep separate from regular wash.'),
      intakeRecordedBy: '00000000-0000-4000-8000-000000000001',
      createdBy: '00000000-0000-4000-8000-000000000001',
      createdAt: Value(now),
      updatedAt: Value(now),
    ),
    OrdersCompanion.insert(
      id: '00000000-0000-4000-8000-0000AAA01026',
      orderCode: 'AMW-1026',
      customerName: 'Grace A.',
      phone: '+256 702 222 111',
      address: 'Nakulabye, close to Shell',
      serviceType: 'Iron only',
      status: 'ready',
      intakeMethod: 'driver_pickup',
      fulfillmentMethod: 'delivery',
      itemCount: 6,
      notes: const Value('Call before delivery.'),
      intakeRecordedBy: '00000000-0000-4000-8000-000000000001',
      createdBy: '00000000-0000-4000-8000-000000000001',
      createdAt: Value(now),
      updatedAt: Value(now),
    ),
    OrdersCompanion.insert(
      id: '00000000-0000-4000-8000-0000AAA01027',
      orderCode: 'AMW-1027',
      customerName: 'Daniel M.',
      phone: '+256 703 333 222',
      address: 'Bwaise, main road',
      serviceType: 'Wash only',
      status: 'completed',
      intakeMethod: 'driver_pickup',
      fulfillmentMethod: 'delivery',
      itemCount: 5,
      notes: const Value('Paid in cash at pickup.'),
      intakeRecordedBy: '00000000-0000-4000-8000-000000000001',
      createdBy: '00000000-0000-4000-8000-000000000001',
      createdAt: Value(now),
      updatedAt: Value(now),
    ),
  ];
}
```

- [ ] **Step 4: Confirm GREEN**.

- [ ] **Step 5: Commit**

```bash
git add lib/src/data/orders_seeder.dart test/data/orders_seeder_test.dart
git commit -m "Add OrdersSeeder for first-launch demo data"
```

### Task 8: Wire `OrdersSeeder` into `AppBootstrap`

So the seed runs once on first launch, after Supabase.initialize.

**Files:**
- Modify: `lib/src/bootstrap/app_bootstrap.dart`
- Modify: `test/widget_test.dart` or a new `test/bootstrap/app_bootstrap_test.dart` (see Step 1)

- [ ] **Step 1: Failing test** in a new `test/bootstrap/app_bootstrap_seeder_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:amuwak_staff/src/bootstrap/app_bootstrap.dart';
import 'package:amuwak_staff/src/data/app_database.dart';
import 'package:amuwak_staff/src/data/orders_seeder.dart';

void main() {
  test('AppBootstrap.runSeed seeds the orders table once', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await AppBootstrap.runSeed(db, OrdersSeeder(clock: () => DateTime.utc(2026, 5, 21)));
    final rows = await db.select(db.orders).get();
    expect(rows, hasLength(4));
    await db.close();
  });
}
```

(`runSeed` is the new public entry — `initialize` calls it internally with the real DB.)

- [ ] **Step 2: Confirm RED**.

- [ ] **Step 3: Implementation** in `lib/src/bootstrap/app_bootstrap.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/app_database.dart';
import '../data/orders_seeder.dart';
import 'app_config.dart';

class AppBootstrap {
  const AppBootstrap._();

  static Future<void> initialize() async {
    WidgetsFlutterBinding.ensureInitialized();
    final config = AppConfig.fromEnvironment()..validate();
    await Supabase.initialize(
      url: config.supabaseUrl,
      anonKey: config.supabaseAnonKey,
    );
    await runSeed(AppDatabase(), OrdersSeeder());
  }

  /// Test-visible seed entry — accepts an injected DB + seeder so tests
  /// don't have to spin up Supabase.
  static Future<void> runSeed(AppDatabase db, OrdersSeeder seeder) =>
      seeder.seedIfEmpty(db);
}
```

- [ ] **Step 4: Confirm GREEN**.

- [ ] **Step 5: Commit**

```bash
git add lib/src/bootstrap/app_bootstrap.dart test/bootstrap/app_bootstrap_seeder_test.dart
git commit -m "Run OrdersSeeder.seedIfEmpty from AppBootstrap"
```

### Task 9: Migrate `StaffDashboardScreen` to the stream

**Files:**
- Modify: `lib/src/dashboard/staff_dashboard_screen.dart`
- Modify: `test/dashboard/staff_dashboard_screen_test.dart`

- [ ] **Step 1: Failing tests** in `test/dashboard/staff_dashboard_screen_test.dart`:

First, add a shared pump helper at the top of the test file that wires Riverpod + an in-memory DB so each test can decide what to seed:

```dart
Future<AppDatabase> pumpDashboardWithDb(
  WidgetTester tester, {
  bool lostPhoto = false,
  List<Override> extraOverrides = const [],
}) async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        ...extraOverrides,
      ],
      child: MaterialApp(
        home: StaffDashboardScreen(retrieveLostPhoto: () async => lostPhoto),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return db;
}
```

Migrate the existing tests (lost-photo SnackBar, no-lost-photo, Notifications tap, New pickup tap, Check order tap, plus the 4 SyncStatusBanner tests from Plan 3a Task 14) to use this helper. Each test that needs to seed data calls `OrdersRepository(db, outbox: OutboxRepository(db), ...).upsertOrder(...)` BEFORE `pumpDashboardWithDb` (or seeds via `db.into(db.orders).insert(...)` directly for simpler cases).

Then add:

```dart
testWidgets('renders an order card for each row in ordersStreamProvider',
    (tester) async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  final outbox = OutboxRepository(db);
  final repo = OrdersRepository(db,
    outbox: outbox,
    clock: () => DateTime.utc(2026, 5, 21),
    uuid: () => 'mut-1',
  );
  await repo.upsertOrder(
    const LaundryOrder(
      orderId: 'X', customerName: 'Test', serviceType: 'wash',
      status: OrderStatus.pendingPickup, timeLabel: '10:00 AM',
      itemCount: 1, phone: 'p', address: 'a', notes: '',
    ),
    actorStaffId: 's-1',
  );

  await tester.pumpWidget(ProviderScope(
    overrides: [appDatabaseProvider.overrideWithValue(db)],
    child: MaterialApp(home: StaffDashboardScreen(retrieveLostPhoto: () async => false)),
  ));
  await tester.pumpAndSettle();

  expect(find.text('Test'), findsOneWidget);

  await db.close();
});

testWidgets('renders an empty list (no crash) while the stream is loading',
    (tester) async {
  // Override ordersStreamProvider with a stream that never emits.
  await tester.pumpWidget(ProviderScope(
    overrides: [
      ordersStreamProvider.overrideWith((ref) => const Stream.empty()),
    ],
    child: MaterialApp(home: StaffDashboardScreen(retrieveLostPhoto: () async => false)),
  ));
  await tester.pump();
  expect(find.text('Assigned orders'), findsOneWidget); // header still there
});

testWidgets('shows the retry button when the stream emits an error',
    (tester) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      ordersStreamProvider.overrideWith((ref) => Stream.error(Exception('boom'))),
    ],
    child: MaterialApp(home: StaffDashboardScreen(retrieveLostPhoto: () async => false)),
  ));
  await tester.pump();
  await tester.pump();
  expect(find.textContaining('Could not load orders'), findsOneWidget);
  expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
});
```

- [ ] **Step 2: Confirm RED**.

- [ ] **Step 3: Implementation** in `lib/src/dashboard/staff_dashboard_screen.dart`:

Convert `StaffDashboardScreen extends StatefulWidget` → `extends ConsumerStatefulWidget`. State class becomes `ConsumerState<StaffDashboardScreen>`. Delete `_orders`, `_replaceUpdatedOrder`, and the in-memory mutation tail of `_openOrderDetails`. In `build`:

```dart
@override
Widget build(BuildContext context) {
  final ordersAsync = ref.watch(ordersStreamProvider);
  return Scaffold(
    backgroundColor: amuwakBackground,
    appBar: /* unchanged */,
    body: SafeArea(
      child: Column(
        children: [
          const SyncStatusBanner(),
          Expanded(
            child: ordersAsync.when(
              data: (orders) => _DashboardBody(orders: orders, onOrderTap: _openOrderDetails),
              loading: () => _DashboardBody(orders: const [], onOrderTap: _openOrderDetails),
              error: (_, __) => _ErrorRetry(onRetry: () => ref.invalidate(ordersStreamProvider)),
            ),
          ),
        ],
      ),
    ),
  );
}
```

Extract the existing ListView render into a private `_DashboardBody({required List<LaundryOrder> orders, required void Function(LaundryOrder) onOrderTap})` widget so the `.when` branches stay short. Add a small `_ErrorRetry` widget (centered Text + `TextButton('Retry')`).

`_openOrderDetails` no longer needs `_replaceUpdatedOrder` — the stream re-emits after the capture screen writes:

```dart
Future<void> _openOrderDetails(LaundryOrder order) async {
  await Navigator.of(context).push<bool>(MaterialPageRoute(
    builder: (_) => OrderDetailsScreen(
      order: order,
      photoStorage: _photoStorage,
      pickPhoto: _pickPhoto,
      cameraViewBuilder: _cameraViewBuilder,
      ordersRepo: ref.read(ordersRepositoryProvider),
      proofEventsRepo: ref.read(proofEventsRepositoryProvider),
      actorStaffId: ref.read(currentUserIdProvider) ?? '',
    ),
  ));
  // No-op on return — the stream picks up the write.
}
```

(`OrderDetailsScreen`'s new params arrive in Task 10; this push site compiles only after Task 10 lands, so commit Task 9 with the dashboard converted to the stream but still passing the OLD `OrderDetailsScreen` constructor for now — see Step 4 below.)

- [ ] **Step 4: Intermediate compile state**

Before Task 10 lands, `OrderDetailsScreen` still has the old constructor. Make the Task 9 commit compile by:
- Keeping the dashboard's push site signature the same as today (only `order`, `photoStorage`, `pickPhoto`, `cameraViewBuilder`).
- Task 10 adds the new required params to `OrderDetailsScreen` AND updates the dashboard push site in the same commit.

- [ ] **Step 5: Confirm GREEN**

`flutter test test/dashboard/staff_dashboard_screen_test.dart`.

- [ ] **Step 6: Commit**

```bash
git add lib/src/dashboard/staff_dashboard_screen.dart test/dashboard/staff_dashboard_screen_test.dart
git commit -m "Swap dashboard to ordersStreamProvider"
```

### Task 9a: Refine dashboard loading branch UX

Follow-up polish to Task 9. Task 9's loading branch renders `_DashboardBody(orders: const [])`, which flashes the summary grid at `0 / 0 / 0 / 0 / 0` and a "Assigned orders" section header with no cards for one frame on cold start. NN/g flags zero-state during loading as misleading — it reads as "no data" rather than "loading." Replace the loading subtree with header banner + slim `LinearProgressIndicator` + quick actions (no summary grid, no orders-section header). Chrome stays tappable; the misleading zero counts disappear.

**Files:**
- Modify: `lib/src/dashboard/staff_dashboard_screen.dart`
- Modify: `test/dashboard/staff_dashboard_screen_test.dart`

- [ ] **Step 1: Update the loading-branch test**

The existing `'renders an empty list (no crash) while the stream is loading'` test asserts the "Assigned orders" section header is visible during loading — that assertion is wrong under the new layout. Rewrite it to:
- Assert `find.byType(LinearProgressIndicator)` resolves to a single widget.
- Assert `find.text('Staff Workspace')` resolves (header banner still rendered).
- Assert `find.text('New pickup')` resolves (quick action still tappable).
- Assert `find.text('Assigned')` finds nothing (no zero-count summary tile).
- Assert `find.text('Assigned orders', skipOffstage: false)` finds nothing (no orders-section header).

Rename the test to `'loading branch shows a progress indicator and no zero-count summary'`.

- [ ] **Step 2: Confirm RED**

`flutter test test/dashboard/staff_dashboard_screen_test.dart` — `find.byType(LinearProgressIndicator)` fails (Task 9's loading branch renders `_DashboardBody`, no indicator anywhere).

- [ ] **Step 3: Implementation** in `lib/src/dashboard/staff_dashboard_screen.dart`:

Extract a new private widget next to `_DashboardBody`:

```dart
class _DashboardLoadingBody extends StatelessWidget {
  const _DashboardLoadingBody();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: const [
        _DashboardHeader(),
        SizedBox(height: 20),
        Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: LinearProgressIndicator(),
        ),
        SizedBox(height: 24),
        _QuickActions(orders: []),
      ],
    );
  }
}
```

Swap the `.when(loading: …)` callback from `() => _DashboardBody(orders: const [], onOrderTap: _openOrderDetails)` to `() => const _DashboardLoadingBody()`.

- [ ] **Step 4: Confirm GREEN**

`flutter test test/dashboard/staff_dashboard_screen_test.dart`.

- [ ] **Step 5: Analyze + commit**

```bash
flutter analyze lib/src/dashboard/staff_dashboard_screen.dart test/dashboard/staff_dashboard_screen_test.dart
git add lib/src/dashboard/staff_dashboard_screen.dart test/dashboard/staff_dashboard_screen_test.dart docs/superpowers/plans/2026-05-21-plan-3b-orders-stream-migration.md
git commit -m "Refine dashboard loading branch UX (Plan 3b Task 9a)"
```

### Task 10: Migrate `OrderDetailsScreen` to write through `OrdersRepository`

**Files:**
- Modify: `lib/src/orders/order_details_screen.dart`
- Modify: `lib/src/dashboard/staff_dashboard_screen.dart` (push site adds new params)
- Modify: `test/orders/order_details_screen_test.dart`

- [ ] **Step 1: Failing test rewrite**

For each "advance to next status" test, switch from "popped LaundryOrder has the new status" to:
- Pump the screen with an in-memory DB and real `OrdersRepository`.
- Tap the advance button.
- After settle, query the DB: `orders.status == 'ready'` (or whatever target).
- Also assert the outbox has the matching update row.

- [ ] **Step 2: Confirm RED**.

- [ ] **Step 3: Implementation**

Add to `OrderDetailsScreen` constructor:
```dart
const OrderDetailsScreen({
  super.key,
  required this.order,
  required this.photoStorage,
  required this.pickPhoto,
  required this.cameraViewBuilder,
  required this.ordersRepo,
  required this.proofEventsRepo,
  required this.actorStaffId,
});

final OrdersRepository ordersRepo;
final ProofEventsRepository proofEventsRepo;
final String actorStaffId;
```

In `_advanceStatusDirectly`:
```dart
Future<void> _advanceStatusDirectly() async {
  final next = _order.status.nextStatus;
  if (next == null) return;
  try {
    await widget.ordersRepo.updateStatus(
      _order.orderId, next,
      actorStaffId: widget.actorStaffId,
    );
    if (!mounted) return;
    setState(() => _order = _order.copyWith(status: next)); // local optimistic — stream will reconcile
  } catch (e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not save status change — please retry.')),
    );
  }
}
```

Update the dashboard's push site (StaffDashboardScreen) to pass `ordersRepo`, `proofEventsRepo`, `actorStaffId`.

- [ ] **Step 4: Confirm GREEN**.

- [ ] **Step 5: Commit**

```bash
git add lib/src/orders/order_details_screen.dart lib/src/dashboard/staff_dashboard_screen.dart test/orders/order_details_screen_test.dart
git commit -m "Wire OrderDetailsScreen advance-status through OrdersRepository"
```

### Task 11: Migrate `PickupCaptureScreen` to write through both repos

**Files:**
- Modify: `lib/src/orders/proof/pickup_capture_screen.dart`
- Modify: `lib/src/orders/order_details_screen.dart` (push site)
- Modify: `test/orders/proof/pickup_capture_screen_test.dart`

- [ ] **Step 1: Failing test rewrite**

Switch from "popped order has inProgress + pickup ProofEvent" to:
- Pump with in-memory DB; `OrdersRepository` + `ProofEventsRepository` injected.
- After "Done" tap, assert `orders.status == 'in_progress'` AND a `proof_events` row exists with `type == 'pickup'`.
- Outbox has 2 rows (`proof_events` insert + `orders` update).
- Keep the existing "save fails → SnackBar + button re-enabled" test (Bug 2 — `_ThrowingProofPhotoStorage`): the photo-save failure short-circuits before any repo write, so neither the proof_events row nor the orders update should land.

- [ ] **Step 2: Confirm RED**.

- [ ] **Step 3: Implementation**

Constructor gains:
```dart
final OrdersRepository ordersRepo;
final ProofEventsRepository proofEventsRepo;
final String actorStaffId;
String Function() proofEventIdGenerator;  // injectable for deterministic tests
```

Default `proofEventIdGenerator` to `() => const Uuid().v4()`.

`_onDone` replaces the `widget.order.copyWith(...)` + `Navigator.pop(context, updated)` tail with:

```dart
final eventId = widget.proofEventIdGenerator();
final event = ProofEvent(
  id: eventId,
  type: ProofEventType.pickup,
  capturedAt: _clock(),
  count: itemCount,
  photoPaths: savedPhotoPaths,
  notes: notes,
);
try {
  await widget.proofEventsRepo.insertEvent(
    event, orderId: widget.order.orderId, actorStaffId: widget.actorStaffId);
  await widget.ordersRepo.updateStatus(
    widget.order.orderId, OrderStatus.inProgress, actorStaffId: widget.actorStaffId);
  if (!mounted) return;
  Navigator.pop<bool>(context, true);
} catch (e) {
  if (!mounted) return;
  setState(() => _saving = false);
  ScaffoldMessenger.of(context).showSnackBar(/* existing SnackBar */);
}
```

Push site in `OrderDetailsScreen` (`_confirmPickup` or wherever it pushes `PickupCaptureScreen`) passes the new params.

- [ ] **Step 4: Confirm GREEN**.

- [ ] **Step 5: Commit**

```bash
git add lib/src/orders/proof/pickup_capture_screen.dart lib/src/orders/order_details_screen.dart test/orders/proof/pickup_capture_screen_test.dart
git commit -m "Wire PickupCaptureScreen through OrdersRepository + ProofEventsRepository"
```

### Task 12: Migrate `DeliveryCaptureScreen` to write through both repos

Same shape as Task 11 with two single-string deltas: `ProofEventType.pickup` → `.delivery`, and `OrderStatus.inProgress` → `.completed`.

**Files:**
- Modify: `lib/src/orders/proof/delivery_capture_screen.dart`
- Modify: `lib/src/orders/order_details_screen.dart` (push site adds the same three params)
- Modify: `test/orders/proof/delivery_capture_screen_test.dart`

- [ ] **Step 1: Failing test rewrite**

Switch the existing "_markDelivered" tests from "popped order has completed + delivery ProofEvent" to:
- Pump with in-memory DB; real `OrdersRepository` + `ProofEventsRepository` injected.
- After "Mark delivered" tap, assert `orders.status == 'completed'` AND a `proof_events` row exists with `type == 'delivery'`.
- Outbox has 2 rows: `proof_events` insert + `orders` update with `status: 'completed'`.
- The existing failure-path test (photo save throws → SnackBar + button re-enabled) keeps its shape; assert no DB writes landed.

- [ ] **Step 2: Confirm RED**.

- [ ] **Step 3: Implementation**

Constructor gains the same four fields as `PickupCaptureScreen` (Task 11):
```dart
final OrdersRepository ordersRepo;
final ProofEventsRepository proofEventsRepo;
final String actorStaffId;
final String Function() proofEventIdGenerator;
```

`_markDelivered`'s post-photo-save tail becomes:
```dart
final eventId = widget.proofEventIdGenerator();
final event = ProofEvent(
  id: eventId,
  type: ProofEventType.delivery,
  capturedAt: _clock(),
  count: itemCount,       // pickup's count if available, else widget.order.itemCount
  photoPaths: savedPhotoPaths,
  notes: notes,
);
try {
  await widget.proofEventsRepo.insertEvent(
    event, orderId: widget.order.orderId, actorStaffId: widget.actorStaffId);
  await widget.ordersRepo.updateStatus(
    widget.order.orderId, OrderStatus.completed, actorStaffId: widget.actorStaffId);
  if (!mounted) return;
  Navigator.pop<bool>(context, true);
} catch (e) {
  if (!mounted) return;
  setState(() => _saving = false);
  ScaffoldMessenger.of(context).showSnackBar(/* existing SnackBar */);
}
```

Update `OrderDetailsScreen`'s push site for `DeliveryCaptureScreen` to forward `ordersRepo`, `proofEventsRepo`, `actorStaffId`, and the default `proofEventIdGenerator`.

- [ ] **Step 4: Confirm GREEN**.

- [ ] **Step 5: Commit**

```bash
git add lib/src/orders/proof/delivery_capture_screen.dart lib/src/orders/order_details_screen.dart test/orders/proof/delivery_capture_screen_test.dart
git commit -m "Wire DeliveryCaptureScreen through OrdersRepository + ProofEventsRepository"
```

---

## Verification (end-to-end after all tasks)

1. `flutter analyze` — clean (no new warnings).
2. `flutter test` — every per-task suite green; the four pre-existing `widget_test.dart` failures (Empty login / Wrong login / Correct login — broken since Plan 2 commit `7fd976d`) **stay failing**, the rest pass.
3. Manual smoke on device:
   - `flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`
   - Cold start: four demo orders visible (the seeder ran on first launch).
   - Tap an order → advance status → return to dashboard → status chip updates without a pop-payload (the stream re-emitted).
   - Pickup capture flow: confirm → return to dashboard → status chip moves to "In progress".
   - Delivery capture flow: confirm → return to dashboard → status chip moves to "Completed".
   - Toggle airplane mode → the writes still land locally, the outbox count in the banner ticks up, then drains on reconnect.

## What this plan does NOT do (explicitly forwarded)

- **No New Pickup form (PR-B).** That's the next plan; it sits on top of `OrdersRepository.upsertOrder` (built here in Task 4).
- **No customer dedup by phone, no GPS pre-fill, no schedule-for-later UI.** Deferred to PR-B.
- **No conversion of capture screens to `ConsumerWidget`.** They stay `StatefulWidget` with constructor injection — deliberate to minimize migration surface.
- **No `LoginScreen` rewrite.** The 3 pre-existing `widget_test.dart` failures stay broken — they test obsolete email/password flow against the current username/PIN screen.
- **No "Sign out" button.** `signOutAndReset` (Plan 3a Task 15) exists and is tested; wiring the UI button is its own micro-plan.
- **No outbox dead-letter UI.** Failed rows still log to console only.
- **No proof-photo upload.** The `proof_events` row writes a `photoPaths: const []` payload — actual Storage upload is Plan 4.
- **No `RefreshIndicator` swipe-to-refresh.** The error-state retry button covers manual refresh; the periodic puller + connectivity-edge covers automatic.

## Risks

1. **Status round-trip drift.** If a future contributor adds a Postgres status that doesn't appear in `OrderStatus._statusFromString` *and* doesn't update `toDbString`, writes will land with a string the read path can't parse. Mitigation: the round-trip test in Task 2 enumerates every enum value; the `_statusFromString` throws StateError on unknowns (Plan 3a behavior).

2. **`OrdersRepository(_db)` without an outbox in tests that only test reads.** Plan 3a tests construct `OrdersRepository(db)` for read-only flows. Task 4 makes outbox optional (the constructor's `outbox:` param defaults to null and write methods throw if it's missing). Existing read-only tests keep compiling.

3. **`ProofEvent` id collision with Drift's generated `ProofEvent` row class.** Already handled in Plan 3a via import aliasing (`drift.ProofEvent`); Task 5 follows the same pattern.

4. **The seeder runs against the real DB on every cold start.** `seedIfEmpty` short-circuits after the first row exists, but on the very first launch it inserts 4 rows. If the puller arrives later and the server has different rows with different ids, you'll have BOTH (seed UUIDs + server UUIDs). Mitigation: seed UUIDs are deterministic and distinct (`...0000AAA01024` etc.) so they won't clash; if collision matters in production, the seeder can be gated on `kDebugMode` or pulled out for non-dev builds.

5. **The capture screens' optimistic local `setState` after `updateStatus` could fight the stream re-emission.** `OrderDetailsScreen._advanceStatusDirectly` updates `_order` locally AND awaits the repo write. If the stream emits a slightly different value between the write and the setState, the local state wins until the next emission. Acceptable for this plan — the discrepancy is sub-second.

6. **`PickupCaptureScreen`'s photo-save-then-write-then-pop chain.** If the proof-events insert succeeds but the orders update fails, we have a proof event without a status change. The Drift transaction guarantees per-method atomicity, but the two repo calls are sequential. Mitigation: log the orphan via the existing SnackBar; full saga handling is out of scope.
