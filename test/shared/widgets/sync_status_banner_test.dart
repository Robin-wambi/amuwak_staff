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

  testWidgets(
      'error banner still surfaces offline + pending context (Bug 2)',
      (t) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(() async => db.close());
    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
    ]);
    addTearDown(container.dispose);

    final outbox = container.read(outboxRepositoryProvider);
    // 2 dead-letters → errorCount == 2.
    for (final id in ['e1', 'e2']) {
      await outbox.enqueue(
        id: id, forTable: 'orders', op: 'update', rowId: id, payload: const {},
      );
      for (var i = 0; i < 6; i++) {
        await outbox.markFailed(id, 'boom');
      }
    }
    // 3 still-pending rows → pendingCount == 3.
    for (final id in ['p1', 'p2', 'p3']) {
      await outbox.enqueue(
        id: id, forTable: 'orders', op: 'update', rowId: id, payload: const {},
      );
    }
    // Device is offline.
    container.read(onlineProvider.notifier).state = false;

    await container.read(outboxDeadLetteredProvider.future);
    await container.read(pullDeadLetteredProvider.future);
    await container.read(pendingOutboxCountProvider.future);

    await t.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(body: SyncStatusBanner(onShowErrors: () {})),
      ),
    ));
    await t.pump();

    // The error state must NOT swallow the offline + pending context.
    expect(find.text('Offline · 3 pending · 2 sync errors — tap to review'),
        findsOneWidget);
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

    expect(find.byIcon(Icons.error_outline), findsNothing);
    expect(find.textContaining('pending'), findsNothing);
  });
}
