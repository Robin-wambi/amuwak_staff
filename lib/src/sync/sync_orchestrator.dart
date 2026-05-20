import 'dart:async';

import 'connectivity_watcher.dart';
import 'outbox_worker.dart';
import 'sync_puller.dart';
import 'valid_transitions_loader.dart';

/// Owns the runtime lifecycle of the sync engine: starts/stops the outbox
/// worker timer, runs a periodic puller, drives the online/offline state
/// callback from connectivity edges, and triggers an extra pullAll on every
/// offline→online transition.
///
/// **Design note — Ref vs callback.** The Plan 3a plan suggests passing
/// Riverpod's [Ref] in here so the orchestrator can flip
/// `onlineProvider.notifier.state`. I deliberately kept this class
/// pure-Dart and accept a `setOnline(bool)` callback instead — the wiring
/// code in Task 12 supplies
/// `(b) => ref.read(onlineProvider.notifier).state = b`. Same effect,
/// trivially testable without spinning up a ProviderContainer.
class SyncOrchestrator {
  SyncOrchestrator({
    required this.worker,
    required this.puller,
    required this.watcher,
    required this.transitions,
    required this.setOnline,
    this.workerInterval = const Duration(seconds: 5),
    this.pullerInterval = const Duration(seconds: 15),
  });

  final OutboxWorker worker;
  final SyncPuller puller;
  final ConnectivityWatcher watcher;
  final ValidTransitionsLoader transitions;
  final void Function(bool isOnline) setOnline;
  final Duration workerInterval;
  final Duration pullerInterval;

  bool _started = false;
  Timer? _pullTimer;

  /// Tracks the currently-running pullAll (immediate, periodic, or
  /// connectivity-triggered) so [stop] can wait for it to settle before
  /// returning. Prevents the sign-out path (Task 15) from truncating
  /// Drift mid-write.
  Future<void>? _inFlightPull;

  Future<void> start() async {
    if (_started) return;
    _started = true;

    worker.start(interval: workerInterval);
    watcher.start(
      onOnline: _handleOnline,
      onOffline: _handleOffline,
    );

    final initiallyOnline = await watcher.isOnline();
    setOnline(initiallyOnline);

    await transitions.loadOnce();

    _kickoffPull();
    _pullTimer = Timer.periodic(pullerInterval, (_) => _kickoffPull());
  }

  Future<void> stop() async {
    if (!_started) return;
    _started = false;

    _pullTimer?.cancel();
    _pullTimer = null;
    worker.stop();
    watcher.dispose();

    final inflight = _inFlightPull;
    if (inflight != null) await inflight;
  }

  /// Manual refresh — pull every registered table now. Used by a "swipe
  /// to refresh" affordance (Plan 3b) and by integration tests.
  Future<void> syncNow() async {
    final f = puller.pullAll();
    _inFlightPull = f.then((_) {}, onError: (_) {});
    await f;
  }

  void _handleOnline() {
    setOnline(true);
    _kickoffPull();
  }

  void _handleOffline() {
    setOnline(false);
  }

  void _kickoffPull() {
    final f = puller.pullAll();
    _inFlightPull = f.then((_) {}, onError: (_) {});
  }
}
