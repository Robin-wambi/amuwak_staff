# Sync Error Bar Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the dashboard's sync-error badge trustworthy — stop connectivity blips from creating false errors, give riders a way to clear genuinely-stuck errors, and surface real errors prominently in plain language.

**Architecture:** A new pure `sync_failure_policy.dart` classifies failures (transient transport vs. permanent server rejection) and maps raw error strings to rider-readable text. The `OutboxWorker` consults it so offline/flaky-network failures no longer count toward the dead-letter budget. `OutboxRepository` gains a `discard` path so poison rows can be cleared. The `SyncErrorsScreen` and the dashboard `SyncStatusBanner` consume the friendly text and the discard action, and the banner gains a prominent, tappable error state.

**Tech Stack:** Flutter, Riverpod, Drift (`NativeDatabase.memory()` for tests), mocktail, supabase_flutter (`PostgrestException`). All test infra already present in `dev_dependencies`.

---

## Root Cause Summary (why these tasks exist)

- **False/stuck errors (primary):** `OutboxWorker._drainOnce`'s generic `catch` calls `repo.markFailed` for *every* exception, including pure connectivity failures, while the worker keeps its 5s timer running even when offline. With `deadLetterAfter = 5`, ~30s offline permanently dead-letters good uploads. → Task 1 + Task 2.
- **Count never clears:** outbox dead-letters can only be *retried* (which re-fails for poison rows), never discarded. → Task 3 + Task 4.
- **Errors invisible/confusing:** only a bare toolbar badge with a raw count; stored messages are raw Postgres/exception text. → Task 4 (friendly text) + Task 5 (prominent banner).

## File Structure

- Create `lib/src/sync/sync_failure_policy.dart` — pure functions `isTransientSyncError`, `friendlySyncError`. No Flutter/Drift imports.
- Modify `lib/src/sync/outbox_worker.dart` — generic catch consults `isTransientSyncError`.
- Modify `lib/src/sync/outbox_repository.dart` — add `discard(id)`.
- Modify `lib/src/sync/sync_errors_screen.dart` — friendly subtitle + Discard button (with confirm).
- Modify `lib/src/shared/widgets/sync_status_banner.dart` — prominent tappable error state via `syncErrorCountProvider` + `onShowErrors` callback.
- Modify `lib/src/dashboard/staff_dashboard_screen.dart` — pass `onShowErrors` into the banner.
- Tests: `test/sync/sync_failure_policy_test.dart` (new), plus additions to `test/outbox_worker_test.dart`, `test/outbox_repository_test.dart`, `test/sync/sync_errors_screen_test.dart`, `test/shared/widgets/sync_status_banner_test.dart` (new).

---

## Task 1: Failure-classification policy (pure)

**Files:**
- Create: `lib/src/sync/sync_failure_policy.dart`
- Test: `test/sync/sync_failure_policy_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/sync/sync_failure_policy_test.dart
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:amuwak_staff/src/sync/sync_failure_policy.dart';

void main() {
  group('isTransientSyncError', () {
    test('treats socket / timeout / client transport errors as transient', () {
      expect(isTransientSyncError(SocketException('failed host lookup')),
          isTrue);
      expect(isTransientSyncError(TimeoutException('slow')), isTrue);
      expect(
          isTransientSyncError(
              Exception('ClientException: Connection closed before full header')),
          isTrue);
      expect(
          isTransientSyncError('Connection refused (os error 111)'),
          isTrue);
    });

    test('treats a Postgrest data rejection as NON-transient', () {
      expect(
          isTransientSyncError(
              const PostgrestException(message: 'duplicate key', code: '23505')),
          isFalse);
    });

    test('treats an unknown-op StateError as NON-transient', () {
      expect(isTransientSyncError(StateError('unknown op "frobnicate"')),
          isFalse);
    });
  });

  group('friendlySyncError', () {
    test('maps null / empty to a generic line', () {
      expect(friendlySyncError(null), 'Could not be saved.');
      expect(friendlySyncError('   '), 'Could not be saved.');
    });

    test('maps known Postgres codes to plain language', () {
      expect(friendlySyncError('23505: duplicate key value'),
          'Already saved on the server.');
      expect(friendlySyncError('23503: violates foreign key constraint'),
          'Linked record is missing on the server.');
      expect(friendlySyncError('new row violates row-level security policy'),
          'Not allowed on the server (permissions).');
      expect(friendlySyncError('JWT expired'),
          'Sign-in expired — sign out and back in.');
    });

    test('maps transport text to a retry message', () {
      expect(friendlySyncError('SocketException: failed host lookup'),
          'Connection problem — will retry automatically.');
    });

    test('falls back to a server-rejected line', () {
      expect(friendlySyncError('42P01: relation does not exist'),
          'Could not be saved (server rejected it).');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/sync/sync_failure_policy_test.dart`
Expected: FAIL — `sync_failure_policy.dart` does not exist / functions undefined.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/src/sync/sync_failure_policy.dart
import 'dart:async';

/// True when [error] is a transient transport/connectivity failure that we
/// should retry indefinitely WITHOUT counting it toward the dead-letter
/// budget. A rider losing signal must never turn good uploads into errors.
///
/// Deliberately conservative: only transport-layer failures qualify. Anything
/// the server actually responded to (e.g. [PostgrestException]) or any logic
/// error (e.g. [StateError]) is treated as permanent so it can still
/// dead-letter and surface to the rider.
bool isTransientSyncError(Object error) {
  if (error is TimeoutException) return true;
  final type = error.runtimeType.toString();
  if (type == 'SocketException' ||
      type == 'ClientException' ||
      type == 'HttpException' ||
      type == 'HandshakeException') {
    return true;
  }
  final msg = error.toString().toLowerCase();
  return msg.contains('socketexception') ||
      msg.contains('clientexception') ||
      msg.contains('failed host lookup') ||
      msg.contains('connection closed') ||
      msg.contains('connection refused') ||
      msg.contains('connection reset') ||
      msg.contains('connection attempt failed') ||
      msg.contains('network is unreachable') ||
      msg.contains('software caused connection abort') ||
      msg.contains('xmlhttprequest'); // web offline
}

/// Maps a stored raw outbox/pull error string to a short, rider-readable
/// line for the SyncErrorsScreen. Keeps the raw text out of the rider's face
/// while [isTransientSyncError] keeps the underlying engine behaviour correct.
String friendlySyncError(String? raw) {
  if (raw == null || raw.trim().isEmpty) return 'Could not be saved.';
  final t = raw.toLowerCase();
  if (t.contains('23505') || t.contains('duplicate')) {
    return 'Already saved on the server.';
  }
  if (t.contains('23503') || t.contains('foreign key')) {
    return 'Linked record is missing on the server.';
  }
  if (t.contains('row-level security') ||
      t.contains('42501') ||
      t.contains('permission') ||
      t.contains('403')) {
    return 'Not allowed on the server (permissions).';
  }
  if (t.contains('jwt') ||
      t.contains('401') ||
      t.contains('not authenticated')) {
    return 'Sign-in expired — sign out and back in.';
  }
  if (isTransientSyncError(raw)) {
    return 'Connection problem — will retry automatically.';
  }
  return 'Could not be saved (server rejected it).';
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/sync/sync_failure_policy_test.dart`
Expected: PASS (all cases).

- [ ] **Step 5: Commit**

```bash
git add lib/src/sync/sync_failure_policy.dart test/sync/sync_failure_policy_test.dart
git commit -m "feat(sync): add failure-classification policy"
```

---

## Task 2: Outbox worker stops dead-lettering transient failures

**Files:**
- Modify: `lib/src/sync/outbox_worker.dart` (the generic `catch` in `_drainOnce`, ~line 87)
- Test: `test/outbox_worker_test.dart` (add cases)

- [ ] **Step 1: Write the failing test**

Append inside the existing `main()` group in `test/outbox_worker_test.dart` (it already imports `dart:async`, `PostgrestException`, etc.; add `import 'dart:io';` at the top for `SocketException`):

```dart
  test(
      'transient (offline) errors do NOT dead-letter: row stays pending with '
      'retryCount 0 no matter how many drains run', () async {
    recorder.throwThis = SocketException('failed host lookup');

    await repo.enqueue(
      id: 'm1', forTable: 'orders', op: 'insert',
      rowId: 'r1', payload: const {},
    );

    // Far more drains than deadLetterAfter (5) — a real offline spell.
    for (var i = 0; i < 10; i++) {
      expect(await worker.drainOnce(), 0);
    }

    final pending = await repo.peekPending(limit: 10);
    expect(pending, hasLength(1),
        reason: 'the row must remain queued, not dead-lettered');
    expect(pending.first.status, 'pending',
        reason: 'offline blips must not flip status to failed/dead_letter');
    expect(pending.first.retryCount, 0,
        reason: 'transient errors must not burn the retry budget');
    expect(await repo.watchDeadLettered().first, isEmpty);
  });

  test('permanent (non-Postgrest) errors still dead-letter after the budget',
      () async {
    recorder.throwThis = StateError('OutboxWorker: unknown op "frobnicate"');

    await repo.enqueue(
      id: 'm1', forTable: 'orders', op: 'insert',
      rowId: 'r1', payload: const {},
    );

    for (var i = 0; i < 6; i++) {
      await worker.drainOnce();
    }

    expect(await repo.peekPending(limit: 10), isEmpty,
        reason: 'dead-lettered rows are excluded from peekPending');
    expect(await repo.watchDeadLettered().first, hasLength(1));
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/outbox_worker_test.dart`
Expected: FAIL — the transient test fails because today's generic `catch` calls `markFailed`, so the row dead-letters (status `dead_letter`, `retryCount` climbs).

- [ ] **Step 3: Write minimal implementation**

In `lib/src/sync/outbox_worker.dart`, add the import:

```dart
import 'sync_failure_policy.dart';
```

Replace the generic `catch` block in `_drainOnce` (currently):

```dart
      } catch (e) {
        await repo.markFailed(row.id, e.toString(),
            deadLetterAfter: deadLetterAfter);
        return sent;
      }
```

with:

```dart
      } catch (e) {
        if (isTransientSyncError(e)) {
          // Connectivity/transport blip — not the row's fault. Leave it
          // pending and stop this drain; the next cycle retries WITHOUT
          // burning the dead-letter budget. Prevents a flaky-signal rider
          // from accumulating false sync errors.
          return sent;
        }
        await repo.markFailed(row.id, e.toString(),
            deadLetterAfter: deadLetterAfter);
        return sent;
      }
```

(The `on PostgrestException` block above it is unchanged — server data rejections still dead-letter.)

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/outbox_worker_test.dart`
Expected: PASS — including the pre-existing `on PostgrestException ... marks failed` test, which is untouched by this change.

- [ ] **Step 5: Commit**

```bash
git add lib/src/sync/outbox_worker.dart test/outbox_worker_test.dart
git commit -m "fix(sync): don't dead-letter transient/offline outbox failures"
```

---

## Task 3: Discard path for poison outbox rows

**Files:**
- Modify: `lib/src/sync/outbox_repository.dart` (add `discard`)
- Test: `test/outbox_repository_test.dart` (add a case)

- [ ] **Step 1: Write the failing test**

Append inside `main()` in `test/outbox_repository_test.dart` (it already sets up `db`/`repo` with `NativeDatabase.memory()`):

```dart
  test('discard permanently removes a dead-lettered row from the queue',
      () async {
    await repo.enqueue(
      id: 'm1', forTable: 'orders', op: 'update',
      rowId: 'r1', payload: const {},
    );
    for (var i = 0; i < 6; i++) {
      await repo.markFailed('m1', 'boom');
    }
    expect(await repo.watchDeadLettered().first, hasLength(1),
        reason: 'row should be dead-lettered after exceeding the budget');

    await repo.discard('m1');

    expect(await repo.watchDeadLettered().first, isEmpty);
    expect(await repo.peekPending(limit: 10), isEmpty);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/outbox_repository_test.dart`
Expected: FAIL — `discard` is not defined on `OutboxRepository`.

- [ ] **Step 3: Write minimal implementation**

In `lib/src/sync/outbox_repository.dart`, add after `requeue`:

```dart
  /// Permanently drops a dead-lettered mutation the rider has chosen to give
  /// up on. Unlike [requeue], this does NOT retry — the local change is
  /// discarded for good. Intended only for `dead_letter` rows surfaced in the
  /// SyncErrorsScreen, where retrying a genuinely-poison row would loop
  /// forever.
  Future<void> discard(String id) {
    return (_db.delete(_db.outbox)..where((t) => t.id.equals(id))).go();
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/outbox_repository_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/src/sync/outbox_repository.dart test/outbox_repository_test.dart
git commit -m "feat(sync): add discard for dead-lettered outbox rows"
```

---

## Task 4: SyncErrorsScreen — friendly text + Discard action

**Files:**
- Modify: `lib/src/sync/sync_errors_screen.dart`
- Test: `test/sync/sync_errors_screen_test.dart` (add cases)

- [ ] **Step 1: Write the failing test**

This file already has a `_pumpScreen` helper that overrides `outboxDeadLetteredProvider` / `pullDeadLetteredProvider` with `Stream.value(...)` and injects a `_MockOutboxRepo` / `_MockPullRepo` (plus `_stubOutboxRow(...)`). Reuse it — do NOT introduce a real in-memory DB here. Two edits:

**(a) Patch the existing test** `'renders outbox dead-letter rows with a Retry button that requeues'` so it stops asserting the raw error string (the subtitle becomes friendly text in Step 3). In that test the stub `lastError` appears **twice** — once in the `when(() => mockOutbox.watchDeadLettered())` stub and once in the `_pumpScreen(outboxRows: [...])` argument. Change both from `'network down'` to `'23505: duplicate key value'`, then replace this assertion:

```dart
      expect(find.textContaining('network down'), findsOneWidget);
```

with:

```dart
      expect(find.text('Already saved on the server.'), findsOneWidget);
      expect(find.textContaining('23505'), findsNothing);
```

**(b) Add a new discard test** using the same harness (mocktail's `verify` is already imported):

```dart
  testWidgets(
      'outbox tile Discard confirms then calls discard', (tester) async {
    final mockOutbox = _MockOutboxRepo();
    when(() => mockOutbox.discard(any())).thenAnswer((_) async {});

    await _pumpScreen(
      tester,
      outboxRows: [
        _stubOutboxRow(
          id: 'k-1', forTable: 'orders', op: 'update', rowId: 'AMW-A',
          lastError: '23505: duplicate key value',
        ),
      ],
      pullRows: const [],
      outboxRepoOverride: mockOutbox,
    );
    await tester.pumpAndSettle();

    // Friendly text replaces the raw "23505: ..." string.
    expect(find.text('Already saved on the server.'), findsOneWidget);
    expect(find.textContaining('23505'), findsNothing);

    // The tile's 'Discard' opens a confirm dialog; the dialog's
    // 'Discard upload' action is what calls repo.discard.
    await tester.tap(find.widgetWithText(TextButton, 'Discard'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Discard upload'));
    await tester.pumpAndSettle();

    verify(() => mockOutbox.discard('k-1')).called(1);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/sync/sync_errors_screen_test.dart`
Expected: FAIL — the new discard test fails (no `discard` on the mock / no Discard button), and the patched retry test fails because the subtitle still renders the raw `23505` text.

- [ ] **Step 3: Write minimal implementation**

In `lib/src/sync/sync_errors_screen.dart`:

1. Add import: `import 'sync_failure_policy.dart';`

2. In the outbox section of the `ListView`, pass an `onDiscard` to the tile alongside the existing `onRetry`:

```dart
                    for (final row in outboxRows)
                      _OutboxErrorTile(
                        row: row,
                        onRetry: () async {
                          try {
                            await ref
                                .read(outboxRepositoryProvider)
                                .requeue(row.id);
                          } catch (e) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Retry failed: $e')),
                            );
                          }
                        },
                        onDiscard: () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (dialogCtx) => AlertDialog(
                              title: const Text('Discard upload?'),
                              content: const Text(
                                'This change could not be saved and will be '
                                'permanently discarded from this device.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(dialogCtx).pop(false),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(dialogCtx).pop(true),
                                  child: const Text('Discard upload'),
                                ),
                              ],
                            ),
                          );
                          if (ok != true) return;
                          try {
                            await ref
                                .read(outboxRepositoryProvider)
                                .discard(row.id);
                          } catch (e) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Discard failed: $e')),
                            );
                          }
                        },
                      ),
```

3. Update `_OutboxErrorTile` to take `onDiscard`, render the friendly subtitle, and show both actions:

```dart
class _OutboxErrorTile extends StatelessWidget {
  const _OutboxErrorTile({
    required this.row,
    required this.onRetry,
    required this.onDiscard,
  });
  final OutboxData row;
  final VoidCallback onRetry;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text('${row.forTable} · ${row.op} · ${row.rowId}'),
        subtitle: Text(
          friendlySyncError(row.lastError),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(onPressed: onRetry, child: const Text('Retry')),
            TextButton(onPressed: onDiscard, child: const Text('Discard')),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/sync/sync_errors_screen_test.dart`
Expected: PASS, including any pre-existing tests in the file (the title text and pull-tile behaviour are unchanged).

- [ ] **Step 5: Commit**

```bash
git add lib/src/sync/sync_errors_screen.dart test/sync/sync_errors_screen_test.dart
git commit -m "feat(sync): friendly error text and discard action on errors screen"
```

---

## Task 5: Prominent, tappable error state in the dashboard banner

**Files:**
- Modify: `lib/src/shared/widgets/sync_status_banner.dart`
- Modify: `lib/src/dashboard/staff_dashboard_screen.dart` (wire `onShowErrors`)
- Test: `test/shared/widgets/sync_status_banner_test.dart` (new)

- [ ] **Step 1: Write the failing test**

```dart
// test/shared/widgets/sync_status_banner_test.dart
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_staff/src/data/app_database.dart';
import 'package:amuwak_staff/src/shared/widgets/sync_status_banner.dart';
import 'package:amuwak_staff/src/sync/repository_providers.dart';
import 'package:amuwak_staff/src/sync/sync_errors_provider.dart';
import 'package:amuwak_staff/src/sync/sync_status.dart';

void main() {
  testWidgets('shows a tappable error row when there are sync errors',
      (t) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(() async => db.close());
    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
    ]);
    addTearDown(container.dispose);

    // Seed 2 outbox dead-letters so syncErrorCountProvider == 2.
    final outbox = container.read(outboxRepositoryProvider);
    for (final id in ['a', 'b']) {
      await outbox.enqueue(
        id: id, forTable: 'orders', op: 'update', rowId: id, payload: const {},
      );
      for (var i = 0; i < 6; i++) {
        await outbox.markFailed(id, 'boom');
      }
    }
    await container.read(outboxDeadLetteredProvider.future);
    await container.read(pullDeadLetteredProvider.future);

    var tapped = 0;
    await t.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: SyncStatusBanner(onShowErrors: () => tapped++),
        ),
      ),
    ));
    await t.pump();

    expect(find.text('2 sync errors — tap to review'), findsOneWidget);
    await t.tap(find.text('2 sync errors — tap to review'));
    expect(tapped, 1);
  });

  testWidgets('hides entirely when online, no pending, no errors', (t) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(() async => db.close());
    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
    ]);
    addTearDown(container.dispose);

    await t.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(body: SyncStatusBanner()),
      ),
    ));
    await t.pump();

    expect(find.byType(Material), findsWidgets); // Scaffold material only
    expect(find.byIcon(Icons.error_outline), findsNothing);
    expect(find.textContaining('pending'), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/shared/widgets/sync_status_banner_test.dart`
Expected: FAIL — `SyncStatusBanner` has no `onShowErrors` param and renders no error row.

- [ ] **Step 3: Write minimal implementation**

Replace `lib/src/shared/widgets/sync_status_banner.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../sync/sync_errors_provider.dart';
import '../../sync/sync_status.dart';

/// A thin banner shown above the staff dashboard. Priority order:
///   1. Sync errors (red, tappable → opens the sync-errors screen)
///   2. Offline (orange)
///   3. Pending uploads (blue)
/// Hides itself when online, nothing pending, and no errors.
class SyncStatusBanner extends ConsumerWidget {
  const SyncStatusBanner({super.key, this.onShowErrors});

  /// Invoked when the rider taps the error state. The dashboard wires this to
  /// push the SyncErrorsScreen; left null in contexts that can't navigate.
  final VoidCallback? onShowErrors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(syncStatusProvider);
    final errorCount = ref.watch(syncErrorCountProvider);

    if (errorCount > 0) {
      final label =
          '$errorCount sync error${errorCount == 1 ? "" : "s"} — tap to review';
      return Material(
        color: Colors.red.shade100,
        child: InkWell(
          onTap: onShowErrors,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.error_outline,
                    size: 16, color: Colors.red.shade900),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(label,
                      style:
                          TextStyle(color: Colors.red.shade900, fontSize: 13)),
                ),
                Icon(Icons.chevron_right,
                    size: 18, color: Colors.red.shade900),
              ],
            ),
          ),
        ),
      );
    }

    if (s.online && s.pendingCount == 0) {
      return const SizedBox.shrink();
    }
    final bg = !s.online ? Colors.orange.shade100 : Colors.blue.shade100;
    final fg = !s.online ? Colors.orange.shade900 : Colors.blue.shade900;
    final label = !s.online
        ? 'Offline${s.pendingCount > 0 ? " — ${s.pendingCount} pending" : ""}'
        : '${s.pendingCount} pending upload${s.pendingCount == 1 ? "" : "s"}';
    return Material(
      color: bg,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(!s.online ? Icons.cloud_off : Icons.sync, size: 16, color: fg),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: fg, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
```

Then in `lib/src/dashboard/staff_dashboard_screen.dart`, wire the callback. `_DashboardTabShell` builds `const SyncStatusBanner()`; thread an `onShowErrors` through it from the screen state:

In `_StaffDashboardScreenState`, add a helper:

```dart
  void _openSyncErrors() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const SyncErrorsScreen()),
    );
  }
```

Change the `_DashboardTabShell` usage in `build` to pass it:

```dart
      body: _DashboardTabShell(
        onShowErrors: _openSyncErrors,
        child: switch (_selectedTabIndex) {
```

Update `_DashboardTabShell`:

```dart
class _DashboardTabShell extends StatelessWidget {
  const _DashboardTabShell({required this.child, this.onShowErrors});

  final Widget child;
  final VoidCallback? onShowErrors;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          SyncStatusBanner(onShowErrors: onShowErrors),
          Expanded(child: child),
        ],
      ),
    );
  }
}
```

(`SyncErrorsScreen` is already imported in the dashboard file.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/shared/widgets/sync_status_banner_test.dart`
Expected: PASS.
Run: `flutter test test/dashboard/staff_dashboard_screen_test.dart`
Expected: PASS — confirms the dashboard wiring still builds (note: this file must be run on its own per the host's one-file-at-a-time constraint).

- [ ] **Step 5: Commit**

```bash
git add lib/src/shared/widgets/sync_status_banner.dart lib/src/dashboard/staff_dashboard_screen.dart test/shared/widgets/sync_status_banner_test.dart
git commit -m "feat(sync): prominent tappable error state in dashboard banner"
```

---

## Final verification

- [ ] `flutter analyze` is clean.
- [ ] Run each touched test file individually (host constraint — never pass multiple paths to `flutter test`):
  - `flutter test test/sync/sync_failure_policy_test.dart`
  - `flutter test test/outbox_worker_test.dart`
  - `flutter test test/outbox_repository_test.dart`
  - `flutter test test/sync/sync_errors_screen_test.dart`
  - `flutter test test/shared/widgets/sync_status_banner_test.dart`
  - `flutter test test/sync/sync_errors_provider_test.dart` (regression — unchanged, must stay green)
  - `flutter test test/dashboard/staff_dashboard_screen_test.dart` (regression)

## Manual smoke (verify / run skill)

1. Sign in, create a pickup, turn off Wi-Fi/data for >30s. **Expect:** banner shows "Offline — N pending"; the error badge stays 0; nothing dead-letters. Restore connectivity → uploads drain, banner clears.
2. Force a permanent failure (e.g. a payload the server rejects with a constraint error). **Expect:** after the retry budget, a red "N sync errors — tap to review" banner; tap → SyncErrorsScreen shows plain-language text; Discard clears it and the badge drops to 0.

## Testing Strategy
- Pure policy logic (Task 1) is exhaustively unit-tested with no Flutter/Drift deps.
- Worker behaviour (Task 2) uses the existing in-memory Drift + dispatch-recorder harness, asserting both the transient (no dead-letter) and permanent (still dead-letters) paths.
- Repository (Task 3) and UI (Tasks 4–5) use the existing `NativeDatabase.memory()` + `ProviderContainer` patterns already established in the suite.

## Rollback Plan
- Each task is its own commit; `git revert` the relevant commit(s). No schema/migration changes, so rollback is code-only and safe.

## Scoped-commit reminder
Commit with the explicit paths shown in each task (`git add <paths>`) to avoid bundling unrelated pre-staged work on this shared `feature/staff-bottom-navigation` branch.
