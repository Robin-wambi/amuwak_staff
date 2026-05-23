# Plan 4 — Sync Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the remaining real-bug gaps surfaced by the post-Plan-3b code review: make outbox dedup structural (not a UI band-aid), survive single bad rows on the pull side without stopping a whole table's sync, surface dead-lettered rows to the rider, and add genuine widget coverage for the login flow.

**Architecture:** Three layers get touched. (1) `OutboxRepository.enqueue` switches from caller-supplied UUIDs to a documented deterministic-key contract — same logical mutation produces the same key across retries, so `insertOrIgnore` at the SQL layer becomes a real idempotency guarantee instead of a happenstance. (2) `SyncPuller.pullTable` gains per-row try/catch with a new `pull_dead_letter` table — a bad row gets quarantined and the watermark advances past it. (3) A new dashboard badge + `SyncErrorsScreen` lists both outbox dead-letters and pull-side dead-letters, with retry for the outbox side. (4) New `test/auth/login_screen_test.dart` covers form validation, the success path, and the failure path with a mocked AuthService.

**Tech Stack:** Dart 3.8, Flutter, Drift 2.x, supabase_flutter 2.x, flutter_riverpod 2.5, mocktail.

**Source spec:** none — this plan is driven by post-Plan-3b code review findings.
**Prerequisite plan:** [2026-05-21-plan-3b-orders-stream-migration.md](2026-05-21-plan-3b-orders-stream-migration.md) (merged through Task 12a + the 17 review-fix commits).

---

## Context

Plan 3b shipped the orders-stream + capture-screen rewrite and went through a two-reviewer audit. Five Critical and six Important issues were landed (commits `719bd95..877ca1d`), but the review surfaced four issues whose proper fix needs more than a one-commit drive-by:

1. **Outbox mutation IDs are not deterministic.** Capture-screen retries now cache a UI-layer `_pendingEventId` + `_proofPersisted` flag, which works for those two screens. But any future repo write that's retried (a new pickup form, a status-toggle button, a background sweep) will mint a fresh UUID and double-enqueue. This plan moves the dedup contract from the UI down into the outbox itself.

2. **A single malformed row aborts a whole table's pull cycle.** Pre-existing TODO at `sync_puller.dart:104`. If Supabase ships one row that the mapper can't parse (null in a non-null column, schema drift, etc.), the entire batch's transaction aborts and the watermark doesn't advance — the rider's dashboard stops getting updates for that table until the bad row is fixed server-side. Mirror what the outgoing outbox already does: quarantine the bad row, log the error, advance past it.

3. **No UI surfaces dead-lettered rows.** The outbox already moves rows to `'dead_letter'` status after 5 failed retries ([outbox_repository.dart:58](../../lib/src/sync/outbox_repository.dart#L58)), but no screen reads `peekDeadLettered`. Add pull-side dead-letters from Task 2 and the rider is blind to both. A dashboard badge + a `SyncErrorsScreen` closes the silent-data-loss loop.

4. **`widget_test.dart` login tests are skipped** (Plan 3b Critical #4 fix). The skipped tests were obsolete email/password fixtures; the actual username/PIN login flow has zero widget coverage. New dedicated tests against the real LoginScreen.

## Locked-in decisions

- **Outbox keys remain caller-supplied** (not derived from payload internals) so callers stay explicit about what "the same mutation" means. A helper `Outbox.dedupKeyFor(...)` centralises the format. `enqueue` keeps its `id:` param.
- **`updateStatus` accepts an optional `updatedAt` param** for callers that need stable mutation keys across retries. Default is `_clock()` (current production behaviour). Capture screens cache their first `_clock()` value and pass it on retry, replacing the C2 `_proofPersisted` flag.
- **Pull-side dead-letter is a new Drift table** (`pull_dead_letter`), not a column on `sync_watermarks`. Reason: failures stack per-row and need their own queryable schema.
- **Pull dead-letters are NOT retried automatically.** They're surfaced read-only in the SyncErrorsScreen with a "Server fix required" badge. Server-side rows can be republished by the back office.
- **Outbox dead-letters get a one-tap retry** in the UI (resets `retry_count` to 0, flips status back to `'pending'`).
- **Drift `schemaVersion` bumps from 1 → 2.** First real migration on this DB. Add `MigrationStrategy.onUpgrade` that creates the `pull_dead_letter` table.
- **Login tests live in a new file** (`test/auth/login_screen_test.dart`). The three skipped tests in `widget_test.dart` get deleted; the `App opens to login` test stays.

## Architecture

```
Task 1 — Login widget tests (independent, no production code touched)
  test/auth/login_screen_test.dart  → mocks AuthService, asserts validate/login/error paths

Task 2 — Deterministic outbox dedup
  OutboxRepository
    static String dedupKeyFor({forTable, op, rowId, [extra])   [new]
    enqueue(id, ...)                                            [doc updated; behaviour unchanged]

  OrdersRepository
    upsertOrder(order, actorStaffId)
      → outbox.enqueue(id: dedupKeyFor('orders','insert',order.id, extra: updatedAt))
    updateStatus(orderId, newStatus, actorStaffId, [updatedAt])
      → outbox.enqueue(id: dedupKeyFor('orders','update',orderId, extra: updatedAtIso))

  ProofEventsRepository.insertEvent(event, orderId, actorStaffId)
    → outbox.enqueue(id: dedupKeyFor('proof_events','insert',event.id))

  PickupCaptureScreen / DeliveryCaptureScreen
    cache _pendingUpdatedAt = first widget.clock() call
    pass updatedAt: _pendingUpdatedAt to ordersRepo.updateStatus
    remove _proofPersisted flag (outbox dedup is now structural)

Task 3 — Pull-side dead-letter
  AppDatabase schemaVersion: 1 → 2
    + new table: pull_dead_letter(id PK, table_name, row_payload_json, error_text, recorded_at)
    + MigrationStrategy.onUpgrade(1 → 2): create the table

  PullDeadLetterRepository  [new]
    insert(tableName, rowPayload, errorText)
    watchAll() : Stream<List<PullDeadLetterRow>>
    purgeOlderThan(Duration)  [housekeeping; called from worker maybe — out of scope here]

  SyncPuller.pullTable
    Per-row try/catch around mapper.upsert
    On exception: deadLetter.insert(tableName, rowJson, '$e\n$st') + continue
    Watermark advances to max(watermarkColumn) across ALL rows (good + bad)

Task 4 — Dead-letter UI
  syncErrorCountProvider  [new] = StreamProvider<int>
    combines: outbox.peekDeadLettered().length + pullDeadLetter.watchAll().length

  Dashboard AppBar gets new IconButton with badge
    onPressed → push SyncErrorsScreen

  SyncErrorsScreen  [new]
    ListView grouped by source
      - Outbox dead-letters: row | error | [Retry] button (sets retry_count=0, status='pending')
      - Pull dead-letters:   row | error | "Server fix required" badge
```

## File Layout

```
lib/src/
├── auth/
│   └── login_screen.dart                          [unchanged]
├── data/
│   ├── app_database.dart                          [modify — schemaVersion 1→2, MigrationStrategy.onUpgrade]
│   └── tables/
│       └── pull_dead_letter_table.dart            [new]
├── sync/
│   ├── outbox_repository.dart                     [modify — add dedupKeyFor, peekDeadLettered, requeue]
│   ├── orders_repository.dart                     [modify — use dedupKeyFor, add updatedAt param to updateStatus]
│   ├── proof_events_repository.dart               [modify — use dedupKeyFor]
│   ├── pull_dead_letter_repository.dart           [new]
│   ├── sync_puller.dart                           [modify — per-row try/catch + dead-letter]
│   ├── sync_errors_provider.dart                  [new — combined error count + list streams]
│   └── sync_errors_screen.dart                    [new]
├── orders/proof/
│   ├── pickup_capture_screen.dart                 [modify — cache _pendingUpdatedAt, drop _proofPersisted]
│   └── delivery_capture_screen.dart               [modify — same]
└── dashboard/
    └── staff_dashboard_screen.dart                [modify — add sync-errors badge IconButton]

test/
├── auth/
│   └── login_screen_test.dart                     [new]
├── widget_test.dart                               [modify — delete the 3 skipped tests]
├── sync/
│   ├── outbox_repository_test.dart                [modify — dedupKeyFor format, peekDeadLettered, requeue]
│   ├── orders_repository_write_test.dart          [modify — outbox id assertions match deterministic format]
│   ├── proof_events_repository_write_test.dart    [modify — same]
│   ├── pull_dead_letter_repository_test.dart      [new]
│   ├── sync_puller_test.dart                      [modify — bad-row dead-letter assertions]
│   ├── sync_errors_provider_test.dart             [new]
│   └── sync_errors_screen_test.dart               [new]
├── data/
│   └── orders_seeder_test.dart                    [unchanged]
├── orders/proof/
│   ├── pickup_capture_screen_test.dart            [modify — adapt to dedupKeyFor + drop _proofPersisted assertion]
│   ├── delivery_capture_screen_test.dart          [modify — same]
│   └── pickup_delivery_flow_test.dart             [modify — outbox id set comparison stays, but ids change]
└── dashboard/
    └── staff_dashboard_screen_test.dart           [modify — assert sync-errors badge renders + tap navigates]
```

Reuse: `OutboxRepository.markFailed` and the `'dead_letter'` status (Plan 2), `AppDatabase.MigrationStrategy` slot (currently `defaultMigrations`), `pendingOutboxCountProvider` (Plan 3a) pattern for the new `syncErrorCountProvider`, mocktail (already a dev_dependency).

---

## Task list

Each task = one commit. TDD red → green → commit. Use scoped `git commit -m "msg" -- <paths>` per saved memory rule. Run `flutter test <path>` one file at a time (saved memory: multi-path invocations hang on this Windows host). `--` separator goes AFTER `-m` per saved memory.

### Task 1: Login flow widget tests

Plan 3b Critical #4 marked three obsolete login tests `skip: true` so they'd stop masking regressions. The actual username/PIN login flow now has zero widget coverage. This task adds it.

**Files:**
- Create: `test/auth/login_screen_test.dart`
- Modify: `test/widget_test.dart` (delete the 3 skipped tests; keep `App opens to login`)

- [ ] **Step 1: Failing test scaffold** in `test/auth/login_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:amuwak_staff/src/auth/auth_service.dart';
import 'package:amuwak_staff/src/auth/login_screen.dart';
import 'package:amuwak_staff/src/auth/session.dart';
import 'package:amuwak_staff/src/dashboard/staff_dashboard_screen.dart';
import 'package:amuwak_staff/src/sync/repository_providers.dart';
import 'package:amuwak_staff/src/sync/sync_orchestrator_provider.dart';

class _MockAuthService extends Mock implements AuthService {}

Future<void> _pumpLogin(
  WidgetTester tester, {
  required AuthService authService,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authServiceProvider.overrideWithValue(authService),
        // Stub sync-side providers so the dashboard navigation target
        // (after a successful login) builds without Supabase.
        syncLifecycleProvider.overrideWith((ref) {}),
        ordersStreamProvider.overrideWith((ref) => const Stream.empty()),
        pendingOutboxCountProvider
            .overrideWith((ref) => const Stream<int>.empty()),
        lastSyncedAtProvider
            .overrideWith((ref) => const Stream<DateTime?>.empty()),
      ],
      child: const MaterialApp(home: LoginScreen()),
    ),
  );
}

void main() {
  late _MockAuthService auth;

  setUp(() {
    auth = _MockAuthService();
  });

  testWidgets('empty fields show validation messages on tap', (tester) async {
    await _pumpLogin(tester, authService: auth);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Login'));
    await tester.pump();

    expect(find.text('Enter your username'), findsOneWidget);
    expect(find.text('Enter your PIN'), findsOneWidget);
    verifyNever(() => auth.signInWithUsernamePin(
        username: any(named: 'username'), pin: any(named: 'pin')));
  });

  testWidgets('successful login pushes the dashboard', (tester) async {
    when(() => auth.signInWithUsernamePin(
        username: 'rider1', pin: '1234')).thenAnswer((_) async {});

    await _pumpLogin(tester, authService: auth);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Username'),
      'rider1',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'PIN'),
      '1234',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Login'));
    await tester.pumpAndSettle();

    expect(find.byType(StaffDashboardScreen), findsOneWidget);
  });

  testWidgets('AuthFailure shows the error message and stays on login',
      (tester) async {
    when(() => auth.signInWithUsernamePin(
        username: 'rider1',
        pin: '0000')).thenThrow(AuthFailure('Invalid username or PIN'));

    await _pumpLogin(tester, authService: auth);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Username'),
      'rider1',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'PIN'),
      '0000',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Login'));
    await tester.pump();

    expect(find.text('Invalid username or PIN'), findsOneWidget);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(StaffDashboardScreen), findsNothing);
  });
}
```

Need to register the mocktail fallback for the named params at the top of `main()`:

```dart
setUpAll(() {
  registerFallbackValue('');
});
```

- [ ] **Step 2: Run, confirm RED**

`flutter test test/auth/login_screen_test.dart` — should fail because `_MockAuthService` hasn't been written until Step 1 commits, or because the dashboard navigation needs the additional provider overrides above (whichever surfaces first). Refine until each test fails for the RIGHT reason (assertion failure on the assertion of interest), not infrastructure.

- [ ] **Step 3: Delete the 3 skipped tests** in `test/widget_test.dart`. Keep the `App opens to login screen first` test (it's the only one that validates the bootstrap path).

Remove the entire `testWidgets('Empty login fields show validation messages', ...)` block and the two following it. Also remove their guarding skip-comment header since it no longer applies.

- [ ] **Step 4: Run both files, confirm GREEN**

```
flutter test test/auth/login_screen_test.dart
flutter test test/widget_test.dart
```

Both must pass. `widget_test.dart` should show `+1` passed, 0 skipped (down from `+1 ~3`).

- [ ] **Step 5: Analyze + commit**

```bash
flutter analyze test/auth/login_screen_test.dart test/widget_test.dart
git commit -m "Add LoginScreen widget tests; drop obsolete widget_test.dart fixtures" -- test/auth/login_screen_test.dart test/widget_test.dart
```

---

### Task 2: Deterministic outbox mutation keys

Promotes outbox dedup from a UI-layer band-aid (Plan 3b C2's `_proofPersisted` widget-state flag) to a structural guarantee at the `OutboxRepository` layer. Same logical mutation → same dedup key → second `insertOrIgnore` is a no-op at the SQL layer.

**Files:**
- Modify: `lib/src/sync/outbox_repository.dart` — add `static String dedupKeyFor({...})`
- Modify: `lib/src/sync/orders_repository.dart` — use `dedupKeyFor` for both write methods; add optional `updatedAt:` param to `updateStatus`
- Modify: `lib/src/sync/proof_events_repository.dart` — use `dedupKeyFor`
- Modify: `lib/src/orders/proof/pickup_capture_screen.dart` — cache `_pendingUpdatedAt`; drop `_proofPersisted` flag
- Modify: `lib/src/orders/proof/delivery_capture_screen.dart` — same
- Modify: `test/sync/outbox_repository_test.dart` — assert dedupKeyFor format
- Modify: `test/sync/orders_repository_write_test.dart` — adapt id assertions; add idempotency test
- Modify: `test/sync/proof_events_repository_write_test.dart` — adapt id assertions; idempotency test already exists from Plan 3b C2, verify it still passes against the new mechanism
- Modify: `test/orders/proof/pickup_capture_screen_test.dart` — drop `_proofPersisted` assertion (if any); adapt outbox id format
- Modify: `test/orders/proof/delivery_capture_screen_test.dart` — same
- Modify: `test/orders/proof/pickup_delivery_flow_test.dart` — set-based outbox comparison already in place; verify still passes

- [ ] **Step 1: Failing test for `dedupKeyFor` format** in `test/sync/outbox_repository_test.dart`:

```dart
test('dedupKeyFor produces a stable string from (forTable, op, rowId, extra)', () {
  expect(
    OutboxRepository.dedupKeyFor(
      forTable: 'orders',
      op: 'update',
      rowId: 'AMW-A',
      extra: '2026-05-23T12:00:00.000Z',
    ),
    'orders:update:AMW-A:2026-05-23T12:00:00.000Z',
  );
});

test('dedupKeyFor omits extra when absent', () {
  expect(
    OutboxRepository.dedupKeyFor(
      forTable: 'proof_events',
      op: 'insert',
      rowId: 'pe-42',
    ),
    'proof_events:insert:pe-42',
  );
});

test('two enqueue calls with the same dedupKey produce one outbox row', () async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(() async => db.close());
  final outbox = OutboxRepository(db);

  final key = OutboxRepository.dedupKeyFor(
    forTable: 'orders',
    op: 'update',
    rowId: 'AMW-A',
    extra: '2026-05-23T12:00:00.000Z',
  );
  await outbox.enqueue(
    id: key,
    forTable: 'orders',
    op: 'update',
    rowId: 'AMW-A',
    payload: <String, dynamic>{'status': 'ready'},
  );
  await outbox.enqueue(
    id: key,
    forTable: 'orders',
    op: 'update',
    rowId: 'AMW-A',
    payload: <String, dynamic>{'status': 'ready'},
  );

  final rows = await db.select(db.outbox).get();
  expect(rows, hasLength(1));
});
```

- [ ] **Step 2: Run, confirm RED** (`dedupKeyFor` undefined).

- [ ] **Step 3: Implementation** in `lib/src/sync/outbox_repository.dart`. Add the static method above the existing constructor:

```dart
/// Builds a deterministic outbox key. Callers that may retry the same
/// logical mutation (e.g. capture screens after a network blip) MUST pass
/// the SAME key on retry — the outbox's [InsertMode.insertOrIgnore] then
/// makes the second enqueue a SQL-level no-op.
///
/// Format: `forTable:op:rowId[:extra]`. `extra` is typically the row's
/// `updated_at` ISO string so that genuinely-distinct mutations to the
/// same row (e.g. two successive status changes) get distinct keys.
static String dedupKeyFor({
  required String forTable,
  required String op,
  required String rowId,
  String? extra,
}) {
  return extra == null
      ? '$forTable:$op:$rowId'
      : '$forTable:$op:$rowId:$extra';
}
```

- [ ] **Step 4: Run, confirm GREEN** for `outbox_repository_test.dart`.

- [ ] **Step 5: Failing test in `orders_repository_write_test.dart`** — adapt the existing assertions:

The Plan 3b tests assert `outboxRows.single.id == 'mut-1'`. Change to:

```dart
expect(outboxRows.single.id, 'orders:insert:AMW-A:2026-05-21T12:00:00.000Z');
// or for updateStatus:
expect(outboxRows.single.id, 'orders:update:AMW-A:2026-05-21T12:00:00.000Z');
```

And add a new test:

```dart
test('updateStatus called twice with the same updatedAt enqueues ONE outbox row',
    () async {
  await db.into(db.orders).insert(OrdersCompanion.insert(
        id: 'AMW-A',
        orderCode: 'AMW-A',
        customerName: 'S',
        phone: 'p', address: 'a', serviceType: 'wash',
        status: 'in_progress',
        intakeMethod: 'driver_pickup', fulfillmentMethod: 'delivery',
        itemCount: 1,
        intakeRecordedBy: 's-1', createdBy: 's-1',
      ));

  final stableUpdatedAt = DateTime.utc(2026, 5, 21, 12, 0);
  await repo.updateStatus('AMW-A', OrderStatus.readyForDelivery,
      actorStaffId: 's-1', updatedAt: stableUpdatedAt);
  await repo.updateStatus('AMW-A', OrderStatus.readyForDelivery,
      actorStaffId: 's-1', updatedAt: stableUpdatedAt);

  final rows = await db.select(db.outbox).get();
  expect(rows, hasLength(1));
});
```

- [ ] **Step 6: Run, confirm RED** — `updatedAt:` param undefined; id assertions fail.

- [ ] **Step 7: Implementation in `OrdersRepository`** at `lib/src/sync/orders_repository.dart`. Change both write methods:

`upsertOrder`:

```dart
Future<void> upsertOrder(LaundryOrder order,
    {required String actorStaffId}) async {
  final outbox = _requireOutbox();
  final now = _clock();
  await _db.transaction(() async {
    await _db.into(_db.orders).insertOnConflictUpdate(
          _toCompanion(order, actorStaffId, now: now),
        );
    await outbox.enqueue(
      id: OutboxRepository.dedupKeyFor(
        forTable: 'orders',
        op: 'insert',
        rowId: order.orderId,
        extra: now.toUtc().toIso8601String(),
      ),
      forTable: 'orders',
      op: 'insert',
      rowId: order.orderId,
      payload: _toPayload(order, actorStaffId, now: now),
    );
  });
}
```

`updateStatus`:

```dart
Future<void> updateStatus(
  String orderId,
  OrderStatus newStatus, {
  required String actorStaffId,
  DateTime? updatedAt,
}) async {
  final outbox = _requireOutbox();
  final now = updatedAt ?? _clock();
  final dbStatus = newStatus.toDbString();
  await _db.transaction(() async {
    final affected = await (_db.update(_db.orders)
          ..where((t) => t.id.equals(orderId)))
        .write(OrdersCompanion(status: Value(dbStatus), updatedAt: Value(now)));
    if (affected == 0) {
      throw StateError('updateStatus: no order with id "$orderId"');
    }
    await outbox.enqueue(
      id: OutboxRepository.dedupKeyFor(
        forTable: 'orders',
        op: 'update',
        rowId: orderId,
        extra: now.toUtc().toIso8601String(),
      ),
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
```

- [ ] **Step 8: Same shape in `ProofEventsRepository.insertEvent`** at `lib/src/sync/proof_events_repository.dart`. Replace the `id: _uuid()` line with:

```dart
await outbox.enqueue(
  id: OutboxRepository.dedupKeyFor(
    forTable: 'proof_events',
    op: 'insert',
    rowId: event.id,
  ),
  forTable: 'proof_events',
  op: 'insert',
  rowId: event.id,
  payload: <String, dynamic>{ /* unchanged */ },
);
```

(No `extra` needed — `event.id` is the dedup key; proof events are immutable.)

- [ ] **Step 9: Capture-screen plumbing — pass stable `updatedAt`** in `lib/src/orders/proof/pickup_capture_screen.dart`. Cache the value once and pass it on retries:

Add field next to `_pendingCapturedAt`:

```dart
DateTime? _pendingUpdatedAt;
```

In `_onDone`, after the capture block:

```dart
_pendingUpdatedAt ??= widget.clock();
// ... existing proof_events insert ...
try {
  await widget.ordersRepo.updateStatus(
    widget.order.orderId,
    OrderStatus.inProgress,
    actorStaffId: widget.actorStaffId,
    updatedAt: _pendingUpdatedAt,
  );
  // ... existing pop ...
}
```

Drop the `_proofPersisted` flag and the conditional skipping logic that uses it. The proof_events row is now idempotent via its own PK + `insertOrIgnore`, and the orders update is idempotent via the deterministic outbox key — neither needs UI-layer guarding.

Same shape in `lib/src/orders/proof/delivery_capture_screen.dart`'s `_markDelivered`.

- [ ] **Step 10: Adapt the capture-screen retry idempotency tests** in `test/orders/proof/pickup_capture_screen_test.dart` and `delivery_capture_screen_test.dart`. The Plan 3b C2 tests exist and assert "two Done taps with throw-once orders repo produce exactly ONE proof_events row + ONE orders update outbox row". They should still pass against the new mechanism. Update any direct assertions on `outboxRows.single.id` to use the new key format.

- [ ] **Step 11: Run every affected test file**

```
flutter test test/sync/outbox_repository_test.dart
flutter test test/sync/orders_repository_write_test.dart
flutter test test/sync/proof_events_repository_write_test.dart
flutter test test/orders/proof/pickup_capture_screen_test.dart
flutter test test/orders/proof/delivery_capture_screen_test.dart
flutter test test/orders/proof/pickup_delivery_flow_test.dart
```

All green.

- [ ] **Step 12: Analyze + commit**

```bash
flutter analyze lib/src/sync/outbox_repository.dart lib/src/sync/orders_repository.dart lib/src/sync/proof_events_repository.dart lib/src/orders/proof/pickup_capture_screen.dart lib/src/orders/proof/delivery_capture_screen.dart
git commit -m "Make outbox dedup structural via deterministic mutation keys" -- lib/src/sync/outbox_repository.dart lib/src/sync/orders_repository.dart lib/src/sync/proof_events_repository.dart lib/src/orders/proof/pickup_capture_screen.dart lib/src/orders/proof/delivery_capture_screen.dart test/sync/outbox_repository_test.dart test/sync/orders_repository_write_test.dart test/sync/proof_events_repository_write_test.dart test/orders/proof/pickup_capture_screen_test.dart test/orders/proof/delivery_capture_screen_test.dart
```

(Flow test stays green automatically, no edit needed.)

---

### Task 3: Pull-side dead-letter for malformed rows

Closes the TODO at `lib/src/sync/sync_puller.dart:104`. A single bad row from Supabase no longer aborts a whole table's pull cycle.

**Files:**
- Create: `lib/src/data/tables/pull_dead_letter_table.dart`
- Modify: `lib/src/data/app_database.dart` — register the new table, bump `schemaVersion`, add `MigrationStrategy.onUpgrade`
- Create: `lib/src/sync/pull_dead_letter_repository.dart`
- Modify: `lib/src/sync/sync_puller.dart` — per-row try/catch + dead-letter insert + watermark advance
- Create: `test/sync/pull_dead_letter_repository_test.dart`
- Modify: `test/sync_puller_test.dart` — add malformed-row scenarios

- [ ] **Step 1: New table definition** in `lib/src/data/tables/pull_dead_letter_table.dart`:

```dart
import 'package:drift/drift.dart';

class PullDeadLetter extends Table {
  TextColumn     get id              => text()();                      // synthesised: '<table>:<rowId>:<recordedAtMicros>'
  TextColumn     get tableName       => text().named('table_name')();
  TextColumn     get rowPayloadJson  => text().named('row_payload_json')();
  TextColumn     get errorText       => text().named('error_text')();
  DateTimeColumn get recordedAt      => dateTime().named('recorded_at').withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
```

- [ ] **Step 2: Register in `app_database.dart`** — add import, add to `tables:` list, bump `schemaVersion` from 1 to 2, add migration:

```dart
@DriftDatabase(tables: [
  // ...existing tables...
  PullDeadLetter,
])
class AppDatabase extends _$AppDatabase {
  // ...
  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(pullDeadLetter);
      }
    },
  );
}
```

Run `dart run build_runner build` to regenerate `app_database.g.dart`. (If `build_runner` isn't a standing dev_dep, add it; check `pubspec.yaml` `dev_dependencies` before running.)

- [ ] **Step 3: Failing test** in `test/sync/pull_dead_letter_repository_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:amuwak_staff/src/data/app_database.dart';
import 'package:amuwak_staff/src/sync/pull_dead_letter_repository.dart';

void main() {
  late AppDatabase db;
  late PullDeadLetterRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = PullDeadLetterRepository(db);
  });
  tearDown(() async => db.close());

  test('insert + watchAll round-trip', () async {
    await repo.insert(
      tableName: 'orders',
      rowPayload: <String, dynamic>{'id': 'AMW-X', 'status': null},
      errorText: 'TypeError: null is not a String',
      recordedAt: DateTime.utc(2026, 5, 23, 12, 0),
    );

    final rows = await repo.watchAll().first;
    expect(rows, hasLength(1));
    expect(rows.single.tableName, 'orders');
    expect(rows.single.errorText, contains('TypeError'));
  });

  test('two inserts with same tableName + rowId but different recordedAt land both', () async {
    await repo.insert(
      tableName: 'orders',
      rowPayload: <String, dynamic>{'id': 'AMW-X'},
      errorText: 'err 1',
      recordedAt: DateTime.utc(2026, 5, 23, 12, 0),
    );
    await repo.insert(
      tableName: 'orders',
      rowPayload: <String, dynamic>{'id': 'AMW-X'},
      errorText: 'err 2',
      recordedAt: DateTime.utc(2026, 5, 23, 12, 0, 0, 1),
    );

    final rows = await repo.watchAll().first;
    expect(rows, hasLength(2));
  });
}
```

- [ ] **Step 4: Run, confirm RED** — `PullDeadLetterRepository` undefined.

- [ ] **Step 5: Implementation** in `lib/src/sync/pull_dead_letter_repository.dart`:

```dart
import 'dart:convert';
import 'package:drift/drift.dart';
import '../data/app_database.dart';

class PullDeadLetterRepository {
  PullDeadLetterRepository(this._db);
  final AppDatabase _db;

  Future<void> insert({
    required String tableName,
    required Map<String, dynamic> rowPayload,
    required String errorText,
    DateTime? recordedAt,
  }) {
    final now = recordedAt ?? DateTime.now().toUtc();
    final rowId = (rowPayload['id'] ?? '<no-id>').toString();
    final syntheticId =
        '$tableName:$rowId:${now.microsecondsSinceEpoch}';
    return _db.into(_db.pullDeadLetter).insert(
      PullDeadLetterCompanion.insert(
        id: syntheticId,
        tableName: tableName,
        rowPayloadJson: jsonEncode(rowPayload),
        errorText: errorText,
        recordedAt: Value(now),
      ),
      mode: InsertMode.insertOrIgnore,
    );
  }

  Stream<List<PullDeadLetterData>> watchAll() {
    return (_db.select(_db.pullDeadLetter)
          ..orderBy([(t) => OrderingTerm.desc(t.recordedAt)]))
        .watch();
  }
}
```

- [ ] **Step 6: Run, confirm GREEN** for the repo test.

- [ ] **Step 7: Failing test in `sync_puller_test.dart`** — add a section:

```dart
group('Plan 4 Task 3 — per-row dead-letter', () {
  test('a row that the mapper throws on is dead-lettered, good rows still upsert',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(() async => db.close());
    final dlq = PullDeadLetterRepository(db);

    Future<List<Map<String, dynamic>>> fetcher(SyncTable t, DateTime since) async {
      // Two orders rows: one good, one with status==null (mapper throws).
      return [
        {
          'id': 'AMW-OK',
          'order_code': 'AMW-OK',
          'customer_name': 'OK Person',
          'phone': '0', 'address': '0',
          'service_type': 'wash',
          'status': 'pending_pickup',
          'intake_method': 'driver_pickup',
          'fulfillment_method': 'delivery',
          'item_count': 1,
          'intake_recorded_by': 's-1', 'created_by': 's-1',
          'created_at': '2026-05-23T10:00:00Z',
          'updated_at': '2026-05-23T10:00:00Z',
        },
        {
          'id': 'AMW-BAD',
          'status': null,  // mapper will throw
          'updated_at': '2026-05-23T10:01:00Z',
        },
      ];
    }

    final puller = SyncPuller(db: db, fetch: fetcher, deadLetter: dlq);
    final ordersTable = kSyncTables.firstWhere((t) => t.name == 'orders');

    final written = await puller.pullTable(ordersTable);

    // Good row landed.
    final ok = await (db.select(db.orders)..where((t) => t.id.equals('AMW-OK'))).getSingle();
    expect(ok.customerName, 'OK Person');

    // Bad row was dead-lettered.
    final dead = await dlq.watchAll().first;
    expect(dead, hasLength(1));
    expect(dead.single.tableName, 'orders');

    // Watermark advanced past the bad row.
    final w = await (db.select(db.syncWatermarks)..where((t) => t.tableName.equals('orders'))).getSingle();
    expect(w.lastSyncedAt, DateTime.utc(2026, 5, 23, 10, 1, 0));

    // Total written count counts only successful upserts.
    expect(written, 1);
  });
});
```

- [ ] **Step 8: Run, confirm RED** — `SyncPuller` constructor doesn't accept `deadLetter:`.

- [ ] **Step 9: Implementation** in `lib/src/sync/sync_puller.dart`:

Add the optional `PullDeadLetterRepository?` field and per-row try/catch. The transaction wraps all good rows, dead-lettered rows are written outside the transaction so a transaction rollback doesn't lose them.

Replace the inner loop in `pullTable` (around lines 60-80):

```dart
Future<int> pullTable(SyncTable table) async {
  final since = await _readWatermark(table.name);
  final rows = await fetch(table, since);
  if (rows.isEmpty) return 0;

  // Compute the new watermark from the max of every row we SAW (good or
  // bad). A bad row's updated_at still counts — otherwise next cycle
  // re-fetches it and re-dead-letters it forever.
  DateTime? maxWatermark;
  for (final r in rows) {
    final ts = _parseTimestamp(r[table.watermarkColumn]);
    if (ts != null && (maxWatermark == null || ts.isAfter(maxWatermark))) {
      maxWatermark = ts;
    }
  }

  int written = 0;
  await db.transaction(() async {
    for (final r in rows) {
      try {
        await table.upsert(db, r);
        written++;
      } catch (e, st) {
        // Defer dead-letter writes until after the transaction commits
        // so a partial-failure doesn't roll back successful upserts. We
        // buffer the (row, error) tuples here and flush below.
        _failed.add(_FailedRow(table.name, r, e, st));
      }
    }
  });

  // Flush dead-letter rows (no-op if no dlq is wired).
  if (deadLetter != null) {
    for (final f in _failed) {
      await deadLetter!.insert(
        tableName: f.tableName,
        rowPayload: f.row,
        errorText: '${f.error}\n${f.stack}',
      );
    }
  }
  _failed.clear();

  if (maxWatermark != null) {
    await _writeWatermark(table.name, maxWatermark);
  }
  return written;
}
```

The `_FailedRow` struct and `_failed` field are private to the puller:

```dart
final List<_FailedRow> _failed = [];

class _FailedRow {
  _FailedRow(this.tableName, this.row, this.error, this.stack);
  final String tableName;
  final Map<String, dynamic> row;
  final Object error;
  final StackTrace stack;
}
```

Note the transaction-vs-dead-letter ordering: the `try/catch` inside `transaction` catches the mapper error so the transaction itself doesn't abort. Successful upserts commit; failed rows are buffered for post-transaction dead-letter insertion.

- [ ] **Step 10: Wire `deadLetter` into the puller construction at the call site.** Find every `SyncPuller(...)` constructor call in `lib/` and pass `deadLetter: PullDeadLetterRepository(db)`. Likely just `lib/src/sync/sync_orchestrator_provider.dart` lines 26 and 30. Use `ref.watch` for a provider:

In `lib/src/sync/repository_providers.dart`, add:

```dart
final pullDeadLetterRepositoryProvider = Provider<PullDeadLetterRepository>(
  (ref) => PullDeadLetterRepository(ref.watch(appDatabaseProvider)),
);
```

Then update `syncOrchestratorProvider` in `sync_orchestrator_provider.dart`:

```dart
puller: SyncPuller(
  db: db,
  fetch: SyncPuller.supabaseFetcher(supabase),
  deadLetter: ref.watch(pullDeadLetterRepositoryProvider),
),
```

- [ ] **Step 11: Run, confirm GREEN** for the puller test and the repo test.

- [ ] **Step 12: Analyze + commit**

```bash
flutter analyze lib/src/data/tables/pull_dead_letter_table.dart lib/src/data/app_database.dart lib/src/data/app_database.g.dart lib/src/sync/pull_dead_letter_repository.dart lib/src/sync/sync_puller.dart lib/src/sync/sync_orchestrator_provider.dart lib/src/sync/repository_providers.dart
git commit -m "Quarantine malformed pull rows in pull_dead_letter; advance watermark past them" -- lib/src/data/tables/pull_dead_letter_table.dart lib/src/data/app_database.dart lib/src/data/app_database.g.dart lib/src/sync/pull_dead_letter_repository.dart lib/src/sync/sync_puller.dart lib/src/sync/sync_orchestrator_provider.dart lib/src/sync/repository_providers.dart test/sync/pull_dead_letter_repository_test.dart test/sync_puller_test.dart
```

---

### Task 4: Dead-letter UI — badge + SyncErrorsScreen

Surfaces both outbox dead-letters (Plan 2) and pull-side dead-letters (Task 3) to the rider. Without this, both sources can accumulate silently.

**Files:**
- Modify: `lib/src/sync/outbox_repository.dart` — add `Stream<List<OutboxData>> watchDeadLettered()` and `Future<void> requeue(String id)`
- Create: `lib/src/sync/sync_errors_provider.dart`
- Create: `lib/src/sync/sync_errors_screen.dart`
- Modify: `lib/src/dashboard/staff_dashboard_screen.dart` — add a badge IconButton in `actions:` after the existing Notifications + sign-out menu
- Create: `test/sync/sync_errors_provider_test.dart`
- Create: `test/sync/sync_errors_screen_test.dart`
- Modify: `test/dashboard/staff_dashboard_screen_test.dart` — assert badge renders + navigation works

- [ ] **Step 1: Failing test for `OutboxRepository.watchDeadLettered` / `requeue`** in `test/sync/outbox_repository_test.dart`:

```dart
group('dead-letter surface (Plan 4 Task 4)', () {
  test('watchDeadLettered emits rows in dead_letter status, newest first', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(() async => db.close());
    final outbox = OutboxRepository(db);

    await outbox.enqueue(
      id: 'k-pending', forTable: 'orders', op: 'update', rowId: 'A',
      payload: const {},
    );
    await outbox.enqueue(
      id: 'k-failed', forTable: 'orders', op: 'update', rowId: 'B',
      payload: const {},
    );
    // Push k-failed into dead_letter by failing 6 times.
    for (var i = 0; i < 6; i++) {
      await outbox.markFailed('k-failed', 'boom $i');
    }

    final dead = await outbox.watchDeadLettered().first;
    expect(dead.map((r) => r.id).toList(), ['k-failed']);
  });

  test('requeue resets retry_count + flips status back to pending', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(() async => db.close());
    final outbox = OutboxRepository(db);

    await outbox.enqueue(
      id: 'k-stuck', forTable: 'orders', op: 'update', rowId: 'A',
      payload: const {},
    );
    for (var i = 0; i < 6; i++) {
      await outbox.markFailed('k-stuck', 'boom');
    }

    await outbox.requeue('k-stuck');

    final row = await (db.select(db.outbox)..where((t) => t.id.equals('k-stuck'))).getSingle();
    expect(row.status, 'pending');
    expect(row.retryCount, 0);
  });
});
```

- [ ] **Step 2: Confirm RED, then implement** in `outbox_repository.dart`:

```dart
Stream<List<OutboxData>> watchDeadLettered() {
  return (_db.select(_db.outbox)
        ..where((t) => t.status.equals('dead_letter'))
        ..orderBy([(t) => OrderingTerm.desc(t.lastAttemptedAt)]))
      .watch();
}

Future<void> requeue(String id) {
  return (_db.update(_db.outbox)..where((t) => t.id.equals(id))).write(
    const OutboxCompanion(
      status: Value('pending'),
      retryCount: Value(0),
      lastError: Value(null),
      lastAttemptedAt: Value(null),
    ),
  );
}
```

- [ ] **Step 3: Confirm GREEN.**

- [ ] **Step 4: Failing test for combined provider** in `test/sync/sync_errors_provider_test.dart`:

```dart
test('syncErrorCountProvider sums outbox dead-letters + pull dead-letters', () async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(() async => db.close());
  final container = ProviderContainer(overrides: [
    appDatabaseProvider.overrideWithValue(db),
  ]);
  addTearDown(container.dispose);

  // Seed 2 outbox dead-letters.
  final outbox = container.read(outboxRepositoryProvider);
  for (final id in ['a', 'b']) {
    await outbox.enqueue(
      id: id, forTable: 'orders', op: 'update', rowId: id,
      payload: const {},
    );
    for (var i = 0; i < 6; i++) {
      await outbox.markFailed(id, 'boom');
    }
  }
  // Seed 3 pull dead-letters.
  final dlq = container.read(pullDeadLetterRepositoryProvider);
  for (var i = 0; i < 3; i++) {
    await dlq.insert(
      tableName: 'orders',
      rowPayload: {'id': 'p-$i'},
      errorText: 'mapper boom',
    );
  }

  final count = await container.read(syncErrorCountProvider.future);
  expect(count, 5);
});
```

- [ ] **Step 5: Implementation** in `lib/src/sync/sync_errors_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'repository_providers.dart';

/// Combined count of outbox dead-letters + pull-side dead-letters.
/// Drives the dashboard badge.
final syncErrorCountProvider = StreamProvider<int>((ref) {
  final outbox = ref.watch(outboxRepositoryProvider);
  final pullDlq = ref.watch(pullDeadLetterRepositoryProvider);
  // Combine via async generator. Re-emits when either stream ticks.
  return _combineCounts(
    outbox.watchDeadLettered(),
    pullDlq.watchAll(),
  );
});

Stream<int> _combineCounts(Stream<List<Object>> a, Stream<List<Object>> b) async* {
  var aCount = 0;
  var bCount = 0;
  final aSub = a.listen((rows) => aCount = rows.length);
  final bSub = b.listen((rows) => bCount = rows.length);
  try {
    // Wait for at least one emission from each before yielding.
    await Future.wait([a.first.then((r) => aCount = r.length),
                       b.first.then((r) => bCount = r.length)]);
    yield aCount + bCount;
    // Subsequent ticks: yield on each.
    final merged = StreamGroup.merge([a, b]);
    await for (final _ in merged) {
      yield aCount + bCount;
    }
  } finally {
    await aSub.cancel();
    await bSub.cancel();
  }
}
```

(Pull in `package:async/async.dart` for `StreamGroup` — already a transitive dep of flutter, but verify by `flutter pub deps`. If not pulled, add to pubspec.)

Hmm — async-merge with cancel-safety is fiddly. **Simpler alternative**: skip the combiner stream gymnastics, just compute the count by reading both lengths via `Rx.combineLatest2` from rxdart… but rxdart was removed in Plan 3b cleanup. **Cleanest**: do this with two `ref.watch`'d AsyncValues inside the provider, summing the lengths in the build callback. Rewrite as a derived `Provider<int>` that watches two underlying `StreamProvider`s:

```dart
final outboxDeadLetteredProvider = StreamProvider<List<OutboxData>>(
  (ref) => ref.watch(outboxRepositoryProvider).watchDeadLettered(),
);
final pullDeadLetteredProvider = StreamProvider<List<PullDeadLetterData>>(
  (ref) => ref.watch(pullDeadLetterRepositoryProvider).watchAll(),
);

final syncErrorCountProvider = Provider<int>((ref) {
  final outbox = ref.watch(outboxDeadLetteredProvider).valueOrNull ?? const [];
  final pull = ref.watch(pullDeadLetteredProvider).valueOrNull ?? const [];
  return outbox.length + pull.length;
});
```

Much cleaner. Tests pump-and-settle, then read the count.

- [ ] **Step 6: Confirm GREEN.**

- [ ] **Step 7: Failing test for `SyncErrorsScreen`** in `test/sync/sync_errors_screen_test.dart`:

```dart
testWidgets('renders outbox dead-letter rows with a Retry button', (tester) async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(() async => db.close());

  final outbox = OutboxRepository(db);
  await outbox.enqueue(
    id: 'k-1', forTable: 'orders', op: 'update', rowId: 'AMW-A',
    payload: const {'status': 'ready'},
  );
  for (var i = 0; i < 6; i++) {
    await outbox.markFailed('k-1', 'network down');
  }

  await tester.pumpWidget(ProviderScope(
    overrides: [appDatabaseProvider.overrideWithValue(db)],
    child: const MaterialApp(home: SyncErrorsScreen()),
  ));
  await tester.pumpAndSettle();

  expect(find.textContaining('AMW-A'), findsOneWidget);
  expect(find.textContaining('network down'), findsOneWidget);
  expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);

  // Tap Retry → row should leave dead-letter and the list refreshes.
  await tester.tap(find.widgetWithText(TextButton, 'Retry'));
  await tester.pumpAndSettle();
  expect(find.textContaining('AMW-A'), findsNothing);
});

testWidgets('renders pull dead-letter rows as read-only', (tester) async {
  // ...similar shape, asserts no Retry button on pull-side rows.
});
```

- [ ] **Step 8: Implementation** in `lib/src/sync/sync_errors_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_database.dart';
import '../shared/widgets/app_theme.dart';
import 'repository_providers.dart';
import 'sync_errors_provider.dart';

class SyncErrorsScreen extends ConsumerWidget {
  const SyncErrorsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final outboxAsync = ref.watch(outboxDeadLetteredProvider);
    final pullAsync = ref.watch(pullDeadLetteredProvider);

    return Scaffold(
      backgroundColor: amuwakBackground,
      appBar: AppBar(
        backgroundColor: amuwakBackground,
        foregroundColor: amuwakDark,
        elevation: 0,
        title: const Text('Sync errors',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: outboxAsync.when(
          loading: () =>
              const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Could not load: $e')),
          data: (outboxRows) => pullAsync.when(
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Could not load: $e')),
            data: (pullRows) {
              if (outboxRows.isEmpty && pullRows.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No sync errors.',
                        style: TextStyle(color: Colors.black54)),
                  ),
                );
              }
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (outboxRows.isNotEmpty) ...[
                    const _SectionHeader('Pending uploads (retryable)'),
                    for (final row in outboxRows)
                      _OutboxErrorTile(
                        row: row,
                        onRetry: () => ref
                            .read(outboxRepositoryProvider)
                            .requeue(row.id),
                      ),
                  ],
                  if (pullRows.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const _SectionHeader('Server-side data (read-only)'),
                    for (final row in pullRows) _PullErrorTile(row: row),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);
  final String label;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: amuwakDark,
          )),
    );
  }
}

class _OutboxErrorTile extends StatelessWidget {
  const _OutboxErrorTile({required this.row, required this.onRetry});
  final OutboxData row;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text('${row.forTable} · ${row.op} · ${row.rowId}'),
        subtitle: Text(row.lastError ?? 'No error message recorded',
            maxLines: 3, overflow: TextOverflow.ellipsis),
        trailing: TextButton(
          onPressed: onRetry,
          child: const Text('Retry'),
        ),
      ),
    );
  }
}

class _PullErrorTile extends StatelessWidget {
  const _PullErrorTile({required this.row});
  final PullDeadLetterData row;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text('${row.tableName} · server row'),
        subtitle: Text(row.errorText,
            maxLines: 3, overflow: TextOverflow.ellipsis),
        trailing: const Chip(
          label: Text('Server fix required',
              style: TextStyle(fontSize: 11)),
        ),
      ),
    );
  }
}
```

- [ ] **Step 9: Dashboard badge** in `lib/src/dashboard/staff_dashboard_screen.dart`. In the AppBar `actions:`, after the Notifications `IconButton` and before the sign-out PopupMenuButton:

```dart
Consumer(builder: (context, ref, _) {
  final count = ref.watch(syncErrorCountProvider);
  return IconButton(
    tooltip: 'Sync errors',
    icon: Badge(
      label: count > 0 ? Text('$count') : null,
      isLabelVisible: count > 0,
      child: const Icon(Icons.error_outline_rounded),
    ),
    onPressed: () => Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const SyncErrorsScreen()),
    ),
  );
}),
```

- [ ] **Step 10: Failing test** in `test/dashboard/staff_dashboard_screen_test.dart`:

```dart
testWidgets('renders a sync-errors badge with the combined count',
    (tester) async {
  await pumpDashboardWithDb(tester, extraOverrides: [
    outboxDeadLetteredProvider.overrideWith((ref) =>
      Stream<List<OutboxData>>.value(_fakeOutboxRows(2))),
    pullDeadLetteredProvider.overrideWith((ref) =>
      Stream<List<PullDeadLetterData>>.value(_fakePullRows(3))),
  ]);

  expect(find.text('5'), findsOneWidget);  // 2 outbox + 3 pull
  expect(find.byTooltip('Sync errors'), findsOneWidget);
});

testWidgets('tapping the sync-errors badge opens SyncErrorsScreen',
    (tester) async {
  await pumpDashboardWithDb(tester, extraOverrides: [/* same */]);
  await tester.tap(find.byTooltip('Sync errors'));
  await tester.pumpAndSettle();
  expect(find.byType(SyncErrorsScreen), findsOneWidget);
});
```

`_fakeOutboxRows(int)` and `_fakePullRows(int)` are small helper functions at the top of the test file that build N stub `OutboxData` / `PullDeadLetterData` rows.

- [ ] **Step 11: Run all affected tests, one at a time**

```
flutter test test/sync/outbox_repository_test.dart
flutter test test/sync/sync_errors_provider_test.dart
flutter test test/sync/sync_errors_screen_test.dart
flutter test test/dashboard/staff_dashboard_screen_test.dart
```

- [ ] **Step 12: Analyze + commit**

```bash
flutter analyze lib/src/sync/outbox_repository.dart lib/src/sync/sync_errors_provider.dart lib/src/sync/sync_errors_screen.dart lib/src/dashboard/staff_dashboard_screen.dart
git commit -m "Surface outbox + pull dead-letters via dashboard badge and SyncErrorsScreen" -- lib/src/sync/outbox_repository.dart lib/src/sync/sync_errors_provider.dart lib/src/sync/sync_errors_screen.dart lib/src/dashboard/staff_dashboard_screen.dart test/sync/outbox_repository_test.dart test/sync/sync_errors_provider_test.dart test/sync/sync_errors_screen_test.dart test/dashboard/staff_dashboard_screen_test.dart
```

---

## Verification (end-to-end after all tasks)

1. `flutter analyze` — clean. The 3 pre-existing info-level lints (`use_super_parameters` in app_database.dart, two `unnecessary_import` for dart:typed_data) stay; no new issues.
2. `flutter test` — every per-task suite green; whole project still passes (Plan 3b totals were 210 passed / 4 skipped / 0 failed; Plan 4 adds ~25 tests across the four new files, shrinks `widget_test.dart` by 3 skips).
3. Manual smoke:
   - Cold start → dashboard → no error badge visible (clean state).
   - Take a pickup → status changes → no dup proof event in DB or outbox (verify via the deterministic key: manual SELECT against `outbox WHERE rowId = X`).
   - Stop Supabase / disconnect → tap "Confirm pickup" → SnackBar shows; outbox row count goes up to 1 (not 2); reconnect → row drains.
   - Force-dead-letter a row: temporarily change `deadLetterAfter` to 0 in code OR manually `UPDATE outbox SET status='dead_letter'` — confirm badge appears with count, tap → screen renders → tap Retry → row leaves.
   - (Pull dead-letter test is harder to drive locally; covered by the unit test.)

## What this plan does NOT do (explicitly forwarded)

- **No History-panel refresh** on `OrderDetailsScreen`. The just-captured proof event still doesn't show until screen remount. Item #4 from the extracted-bugs list — deferred to its own plan if/when the UX gap becomes painful.
- **No sign-out pending-count warning.** Item #5 — separate micro-plan.
- **No capture-screen "abandon and report" escape hatch** for persistent failures. Item #6 — separate micro-plan.
- **No cleanup of dead read repositories** (`customers/staff/status_events`). Item #8 — defer until PR-B / PR-C decides whether to consume them.
- **No `test/_support/in_memory_db.dart` extraction.** Item #9 — deferred Minor #19; touches 27 files for low immediate value.
- **No commit of the generated_plugin* working-tree files.** Item #10 — needs committing pre-merge as a separate "merge prep" commit (treat as a checklist item for the person opening the merge PR, not a code change).
- **No `LaundryOrder.notes` nullable fix.** Item #11 — pre-existing from Plan 3a; defer.

## Risks

1. **Schema migration on existing devs' DBs.** Plan 4 Task 3 bumps Drift `schemaVersion` from 1 → 2. The `onUpgrade` step only adds the new `pull_dead_letter` table — additive, no destructive changes. But it's the FIRST real migration on this DB; if devs have stale schema cache they may see `MigrationException`. Mitigation: the migration is straightforward `m.createTable(pullDeadLetter)`; tests cover the migration path implicitly by always opening a fresh `NativeDatabase.memory()` at v2. If a real device hits a migration bug, the fix is to delete the local DB file and re-seed.

2. **The `syncErrorCountProvider` uses derived `Provider<int>` reading two StreamProviders.** This pattern is correct in Riverpod 2.5 but requires both stream providers to have emitted at least once before the count is reliable. While loading, the count reads `valueOrNull ?? const []` → 0. Acceptable — no badge during cold start is the same UX as no errors.

3. **`updateStatus`'s new optional `updatedAt:` param changes the production behaviour subtly.** Currently `_clock()` is called per-call; with capture screens now passing a cached value, the DB `updated_at` reflects when "Done" was tapped, not when `updateStatus` actually ran. This is arguably MORE correct (the proof's intent moment, not a microsecond-later DB write). But it's a semantics change; flag in the commit message.

4. **The pull-side dead-letter watermark advancement could lose data** if Supabase later REPUBLISHES the bad row with corrected fields. Today's puller would skip the republish because the row's `updated_at` is older than the watermark. Acceptable for v1 — the dead-letter screen surfaces the issue and a back-office operator can manually re-trigger the row after fixing it. A more durable fix (per-row republish detection) is a follow-up plan.

5. **`SyncErrorsScreen`'s retry button on outbox dead-letters resets `retry_count` to 0.** If the underlying failure is persistent (e.g., RLS rejection because `actorStaffId` is wrong), the row will dead-letter again after 5 more retries. Acceptable — the rider can keep tapping, OR the back office can address the root cause. Not adding deduplication of retry attempts; the worst case is a few extra Supabase calls.

6. **Login widget tests stub `signInWithUsernamePin` via mocktail.** They DON'T exercise the real Supabase call path. Real auth-failure modes (network errors, malformed JWT, RLS) aren't covered — that's integration-test territory. Acceptable: widget tests prove the UI binds to the AuthService correctly; integration tests are a separate concern.
