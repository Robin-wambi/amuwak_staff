import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:amuwak_staff/src/auth/auth_service.dart';
import 'package:amuwak_staff/src/bootstrap/app_config.dart';
import 'package:amuwak_staff/src/data/app_database.dart';
import 'package:amuwak_staff/src/sync/outbox_repository.dart';
import 'package:amuwak_staff/src/sync/outbox_worker.dart';
import 'package:amuwak_staff/src/sync/sync_puller.dart';
import 'package:amuwak_staff/src/sync/sync_registry.dart';

/// End-to-end smoke test: sign in to the real Supabase project, enqueue a
/// new customer via the outbox, drain it through the OutboxWorker, then
/// confirm the SyncPuller round-trips the row back into local Drift.
///
/// This test self-skips when SUPABASE_URL / SUPABASE_ANON_KEY are not
/// provided via --dart-define, so the default `flutter test` run does not
/// hit the network or fail in CI. To execute it:
///
///   $anon = (Select-String '^SUPABASE_ANON_KEY=' .env.local).Line.Split('=',2)[1]
///   flutter test test/end_to_end_sync_test.dart `
///     --dart-define=SUPABASE_URL=https://rrxcsscinwqrxivczrfg.supabase.co `
///     --dart-define=SUPABASE_ANON_KEY=$anon
///
/// Prerequisite: test staff user `testmgr` / PIN `123456` must be seeded in
/// Supabase (see docs/superpowers/plans/2026-05-19-drift-outbox-sync-layer.md
/// Task 11 for the SQL).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  AppConfig? cfg;
  try {
    cfg = AppConfig.fromEnvironment()..validate();
  } on StateError catch (e) {
    test('end-to-end live sync', () {},
        skip:
            'SUPABASE_URL / SUPABASE_ANON_KEY not provided via --dart-define: ${e.message}');
    return;
  }
  final liveCfg = cfg;

  setUpAll(() async {
    // Both side-effects scoped here so they only run when this test actually
    // executes. If the credential-skip path above fires, neither runs and
    // other tests in the suite are unaffected.
    //
    // - TestWidgetsFlutterBinding installs an HttpOverrides that returns 400
    //   to every request; null restores real HTTP for Supabase calls.
    // - shared_preferences has no plugin channel under flutter_test, so we
    //   wire its mock (empty store in memory) before Supabase.initialize.
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues(<String, Object>{});

    await Supabase.initialize(
      url: liveCfg.supabaseUrl,
      anonKey: liveCfg.supabaseAnonKey,
    );
    await AuthService().signInWithUsernamePin(username: 'testmgr', pin: '123456');
  });

  tearDownAll(() async {
    await AuthService().signOut();
  });

  test('round-trip a new customer through outbox + puller', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repo = OutboxRepository(db);
    final supabase = Supabase.instance.client;
    final worker = OutboxWorker(
      repo: repo,
      dispatch: OutboxWorker.supabaseDispatcher(supabase),
      isOnline: () => true,
    );
    final puller = SyncPuller(
      db: db,
      fetch: SyncPuller.supabaseFetcher(supabase),
    );

    // customers.id is a Postgres uuid column — must be valid UUID v4 format
    // (8-4-4-4-12 hex). We use a deterministic prefix + a millis-based tail
    // so concurrent test runs don't collide and the row is identifiable.
    final tail = DateTime.now().millisecondsSinceEpoch
        .toRadixString(16)
        .padLeft(12, '0');
    final newId = 'e2e00000-0000-4000-8000-${tail.substring(tail.length - 12)}';
    final payload = {
      'id': newId,
      'name': 'E2E Sync Test',
      'phone': '+254700009999',
      'address': 'E2E address',
    };

    // 1. Enqueue an insert (offline-style)
    await repo.enqueue(
      id: 'mut-$newId',
      forTable: 'customers',
      op: 'insert',
      rowId: newId,
      payload: payload,
    );
    expect((await repo.peekPending(limit: 10)).length, 1,
        reason: 'enqueue should produce exactly one pending outbox row');

    // 2. Drain the outbox (now online)
    final sent = await worker.drainOnce();
    if (sent == 0) {
      // Diagnostic: surface what the worker recorded so a failure is
      // explainable from a single stdout line.
      final stillPending = await repo.peekPending(limit: 10);
      final dump = stillPending
          .map((r) => '${r.id}: status=${r.status} lastError=${r.lastError}')
          .join(' | ');
      fail('OutboxWorker drained 0 rows. Outbox state: $dump');
    }
    expect(sent, 1, reason: 'drainOnce should send the single queued insert');
    expect(await repo.peekPending(limit: 10), isEmpty,
        reason: 'a successfully-sent row should be removed from the outbox');

    // 3. Pull the customers table; the new row should land locally
    final pulled =
        await puller.pullTable(const SyncTable(name: 'customers'));
    expect(pulled, greaterThan(0));

    final local = await (db.select(db.customers)
          ..where((c) => c.id.equals(newId)))
        .getSingleOrNull();
    expect(local, isNotNull);
    expect(local!.name, 'E2E Sync Test');

    // 4. Cleanup so reruns don't accumulate orphans on the remote
    await supabase.from('customers').delete().eq('id', newId);
    await db.close();
  });
}
