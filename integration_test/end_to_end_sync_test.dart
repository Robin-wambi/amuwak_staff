import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:amuwak_staff/src/auth/auth_service.dart';
import 'package:amuwak_staff/src/bootstrap/app_config.dart';
import 'package:amuwak_staff/src/data/app_database.dart';
import 'package:amuwak_staff/src/sync/outbox_repository.dart';
import 'package:amuwak_staff/src/sync/outbox_worker.dart';
import 'package:amuwak_staff/src/sync/sync_puller.dart';

/// End-to-end smoke test: sign in to the real Supabase project, enqueue a
/// new customer via the outbox, drain it through the OutboxWorker, then
/// confirm the SyncPuller round-trips the row back into local Drift.
///
/// Prerequisites:
///   - SUPABASE_URL and SUPABASE_ANON_KEY passed via --dart-define.
///   - Test staff user `testmgr` / PIN `123456` seeded in Supabase
///     (see docs/superpowers/plans/2026-05-19-drift-outbox-sync-layer.md
///     Task 11 for the SQL).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final cfg = AppConfig.fromEnvironment()..validate();
    await Supabase.initialize(url: cfg.supabaseUrl, anonKey: cfg.supabaseAnonKey);
    final auth = AuthService();
    await auth.signInWithUsernamePin(username: 'testmgr', pin: '123456');
  });

  tearDownAll(() async {
    await AuthService().signOut();
  });

  testWidgets('round-trip a new customer through outbox + puller', (_) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repo = OutboxRepository(db);
    final supabase = Supabase.instance.client;
    final worker = OutboxWorker(
      repo: repo,
      dispatch: OutboxWorker.supabaseDispatcher(supabase),
    );
    final puller = SyncPuller(
      db: db,
      fetch: SyncPuller.supabaseFetcher(supabase),
    );

    final newId = 'e2e-${DateTime.now().millisecondsSinceEpoch}';
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
    expect((await repo.peekPending(limit: 10)).length, 1);

    // 2. Drain the outbox (now online)
    final sent = await worker.drainOnce();
    expect(sent, 1);
    expect(await repo.peekPending(limit: 10), isEmpty);

    // 3. Pull the customers table; the new row should land locally
    final pulled = await puller.pullTable('customers');
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
