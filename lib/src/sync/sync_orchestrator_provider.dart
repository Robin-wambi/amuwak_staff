import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth/session.dart';
import 'connectivity_watcher.dart';
import 'outbox_repository.dart';
import 'outbox_worker.dart';
import 'sync_orchestrator.dart';
import 'sync_puller.dart';
import 'sync_status.dart';
import 'valid_transitions_loader.dart';

/// Builds the singleton [SyncOrchestrator] that owns the sync engine for
/// the current Supabase session. Constructs every primitive (outbox
/// repository, worker, puller, connectivity watcher, transitions loader)
/// inline so tests can override this provider with a mock orchestrator
/// without having to override every dependency too.
final syncOrchestratorProvider = Provider<SyncOrchestrator>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final supabase = Supabase.instance.client;
  return SyncOrchestrator(
    worker: OutboxWorker(
      repo: OutboxRepository(db),
      dispatch: OutboxWorker.supabaseDispatcher(supabase),
    ),
    puller: SyncPuller(db: db, fetch: SyncPuller.supabaseFetcher(supabase)),
    watcher: ConnectivityWatcher(),
    transitions: ValidTransitionsLoader(
      db: db,
      fetch: SyncPuller.supabaseFetcher(supabase),
    ),
    setOnline: (online) =>
        ref.read(onlineProvider.notifier).state = online,
  );
});

/// Side-effecting provider that watches [authStateProvider] and toggles
/// the orchestrator's start/stop based on whether there's a live
/// Supabase session. Must be eagerly `ref.watch`ed somewhere in the
/// widget tree (Task 16 mounts it from `main.dart`) for the lifecycle
/// to fire at all.
///
/// Edge semantics — only the session !=null → session ==null transition
/// (and the reverse) triggers a side effect. Repeated emissions of the
/// same signed-in / signed-out state are no-ops.
final syncLifecycleProvider = Provider<void>((ref) {
  final orchestrator = ref.read(syncOrchestratorProvider);
  bool? lastSignedIn;

  ref.listen<AsyncValue<AuthState>>(
    authStateProvider,
    (prev, next) {
      final signedIn = next.valueOrNull?.session != null;
      if (lastSignedIn == signedIn) return;
      final wasSignedIn = lastSignedIn;
      lastSignedIn = signedIn;
      if (signedIn) {
        orchestrator.start();
      } else if (wasSignedIn == true) {
        // First-ever emission of signed-out is the initial state; there
        // is nothing to stop yet. Only react to a real signed-in →
        // signed-out transition.
        orchestrator.stop();
      }
    },
  );

  ref.onDispose(() {
    orchestrator.stop();
  });
});
