import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:amuwak_staff/src/sync/connectivity_watcher.dart';
import 'package:amuwak_staff/src/sync/outbox_worker.dart';
import 'package:amuwak_staff/src/sync/sync_orchestrator.dart';
import 'package:amuwak_staff/src/sync/sync_puller.dart';
import 'package:amuwak_staff/src/sync/valid_transitions_loader.dart';

class _MockWorker extends Mock implements OutboxWorker {}

class _MockPuller extends Mock implements SyncPuller {}

class _MockWatcher extends Mock implements ConnectivityWatcher {}

class _MockTransitions extends Mock implements ValidTransitionsLoader {}

void main() {
  setUpAll(() {
    registerFallbackValue(Duration.zero);
  });

  late _MockWorker worker;
  late _MockPuller puller;
  late _MockWatcher watcher;
  late _MockTransitions transitions;
  late List<bool> onlineStates;
  late SyncOrchestrator orchestrator;
  late void Function()? capturedOnOnline;
  late void Function()? capturedOnOffline;

  setUp(() {
    worker = _MockWorker();
    puller = _MockPuller();
    watcher = _MockWatcher();
    transitions = _MockTransitions();
    onlineStates = [];
    capturedOnOnline = null;
    capturedOnOffline = null;

    when(() => worker.start(interval: any(named: 'interval'))).thenReturn(null);
    when(() => worker.stop()).thenAnswer((_) async {});
    when(() => puller.pullAll()).thenAnswer((_) async => 0);
    when(() => transitions.loadOnce()).thenAnswer((_) async {});
    when(() => watcher.isOnline()).thenAnswer((_) async => true);
    when(() => watcher.dispose()).thenReturn(null);
    when(() => watcher.start(
          onOnline: any(named: 'onOnline'),
          onOffline: any(named: 'onOffline'),
        )).thenAnswer((invocation) {
      capturedOnOnline =
          invocation.namedArguments[#onOnline] as void Function();
      capturedOnOffline =
          invocation.namedArguments[#onOffline] as void Function()?;
    });

    orchestrator = SyncOrchestrator(
      worker: worker,
      puller: puller,
      watcher: watcher,
      transitions: transitions,
      setOnline: (b) => onlineStates.add(b),
      workerInterval: const Duration(milliseconds: 50),
      pullerInterval: const Duration(milliseconds: 50),
    );
  });

  tearDown(() async {
    await orchestrator.stop();
  });

  group('start()', () {
    test('starts the worker timer with the configured interval', () async {
      await orchestrator.start();
      verify(() => worker.start(interval: const Duration(milliseconds: 50)))
          .called(1);
    });

    test('loads valid_transitions exactly once on startup', () async {
      await orchestrator.start();
      verify(() => transitions.loadOnce()).called(1);
    });

    test('kicks off an immediate pullAll on startup', () async {
      await orchestrator.start();
      // Allow microtasks to drain.
      await Future<void>.delayed(Duration.zero);
      verify(() => puller.pullAll()).called(1);
    });

    test('seeds the setOnline callback from watcher.isOnline()', () async {
      when(() => watcher.isOnline()).thenAnswer((_) async => true);
      await orchestrator.start();
      expect(onlineStates, contains(true));
    });

    test('registers connectivity callbacks via watcher.start()', () async {
      await orchestrator.start();
      verify(() => watcher.start(
            onOnline: any(named: 'onOnline'),
            onOffline: any(named: 'onOffline'),
          )).called(1);
      expect(capturedOnOnline, isNotNull);
      expect(capturedOnOffline, isNotNull);
    });

    test('an online edge triggers another pullAll and reports online=true',
        () async {
      await orchestrator.start();
      await Future<void>.delayed(Duration.zero);
      // 1 immediate pullAll from startup.
      verify(() => puller.pullAll()).called(1);

      capturedOnOnline!();
      await Future<void>.delayed(Duration.zero);

      verify(() => puller.pullAll()).called(1);
      expect(onlineStates.last, isTrue);
    });

    test('an offline edge reports online=false and does NOT trigger pullAll',
        () async {
      await orchestrator.start();
      await Future<void>.delayed(Duration.zero);
      clearInteractions(puller);

      capturedOnOffline!();
      await Future<void>.delayed(Duration.zero);

      verifyNever(() => puller.pullAll());
      expect(onlineStates.last, isFalse);
    });

    test('is idempotent: a second start() does not re-arm timers or re-load',
        () async {
      await orchestrator.start();
      await Future<void>.delayed(Duration.zero);
      clearInteractions(worker);
      clearInteractions(puller);
      clearInteractions(transitions);
      clearInteractions(watcher);

      await orchestrator.start();
      await Future<void>.delayed(Duration.zero);

      verifyNever(() => worker.start(interval: any(named: 'interval')));
      verifyNever(() => transitions.loadOnce());
      verifyNever(() => watcher.start(
            onOnline: any(named: 'onOnline'),
            onOffline: any(named: 'onOffline'),
          ));
      verifyNever(() => puller.pullAll());
    });

    test('the periodic pull timer fires pullAll on its cadence', () async {
      await orchestrator.start();
      await Future<void>.delayed(Duration.zero);
      // 1 from immediate kick-off.
      verify(() => puller.pullAll()).called(1);

      // Wait for ~2 tick intervals so the timer fires at least twice.
      await Future<void>.delayed(const Duration(milliseconds: 130));
      verify(() => puller.pullAll()).called(greaterThanOrEqualTo(2));
    });

    test(
        'a failed transitions.loadOnce leaves orchestrator retryable and '
        'tears down side-effects', () async {
      var loadCalls = 0;
      when(() => transitions.loadOnce()).thenAnswer((_) async {
        loadCalls++;
        if (loadCalls == 1) {
          throw StateError('offline at first sign-in');
        }
      });

      await expectLater(orchestrator.start(), throwsA(isA<StateError>()));

      // Side-effects from the half-started call must be torn down so the
      // worker timer and connectivity stream don't keep running.
      verify(() => worker.stop()).called(1);
      verify(() => watcher.dispose()).called(1);

      // The retry must fully start the orchestrator — including arming the
      // periodic pull timer, not just the connectivity-triggered pulls.
      await orchestrator.start();
      await Future<void>.delayed(Duration.zero);
      verify(() => puller.pullAll()).called(1);

      await Future<void>.delayed(const Duration(milliseconds: 130));
      verify(() => puller.pullAll()).called(greaterThanOrEqualTo(2));
    });
  });

  group('stop()', () {
    test('stops the worker, disposes the watcher, halts the pull timer',
        () async {
      await orchestrator.start();
      await Future<void>.delayed(Duration.zero);

      await orchestrator.stop();

      verify(() => worker.stop()).called(1);
      verify(() => watcher.dispose()).called(1);

      // After stop the periodic pull timer should not fire any more.
      clearInteractions(puller);
      await Future<void>.delayed(const Duration(milliseconds: 130));
      verifyNever(() => puller.pullAll());
    });

    test('is safe to call before start()', () async {
      await expectLater(orchestrator.stop(), completes);
      verifyNever(() => worker.stop());
      verifyNever(() => watcher.dispose());
    });

    test('awaits any in-flight pullAll before returning', () async {
      // Make pullAll resolve on a controllable completer so we can verify
      // the orchestrator's stop() awaits it.
      final inflight = Completer<int>();
      when(() => puller.pullAll())
          .thenAnswer((_) async => inflight.future);

      await orchestrator.start();
      // start() awaits transitions.loadOnce + watcher.isOnline, then kicks
      // off pullAll without awaiting. The future is now sitting in flight.

      // Begin stop() — it should not complete until inflight resolves.
      final stopFuture = orchestrator.stop();
      var stopCompleted = false;
      stopFuture.then((_) => stopCompleted = true);

      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(stopCompleted, isFalse,
          reason: 'stop should be waiting on the in-flight pullAll');

      inflight.complete(0);
      await stopFuture;
      expect(stopCompleted, isTrue);
    });
  });

  group('syncNow()', () {
    test('triggers an extra pullAll on demand', () async {
      await orchestrator.start();
      await Future<void>.delayed(Duration.zero);
      clearInteractions(puller);

      await orchestrator.syncNow();

      verify(() => puller.pullAll()).called(1);
    });
  });
}
