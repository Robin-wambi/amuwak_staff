import 'dart:async';
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'outbox_repository.dart';
import 'sync_failure_policy.dart';

/// Function called for each row drained from the outbox. Implementations
/// throw to signal failure; the worker will catch and call repo.markFailed.
typedef OutboxDispatch = Future<void> Function(
  String forTable,
  String op,
  String rowId,
  Map<String, dynamic> payload,
);

class OutboxWorker {
  OutboxWorker({
    required this.repo,
    required this.dispatch,
    this.isOnline,
    this.batchSize = 25,
    this.deadLetterAfter = 5,
  });

  final OutboxRepository repo;
  final OutboxDispatch dispatch;

  /// Reports whether the device currently has connectivity. Used to tell an
  /// offline blip (skip without penalty) apart from an online, row-specific
  /// transient failure (must count toward the dead-letter budget so a poison
  /// head row can't block the queue forever). When null, the worker assumes
  /// offline — the conservative choice that never dead-letters a transient
  /// error, at the cost of head-of-line blocking until connectivity is wired.
  final bool Function()? isOnline;

  final int batchSize;

  /// After this many failed attempts the row is parked in `dead_letter`
  /// status so it stops blocking later mutations. A separate UI / admin
  /// flow surfaces dead-lettered rows for manual review.
  final int deadLetterAfter;

  Timer? _timer;

  /// Tracks the currently-running drainOnce so [stop] can await it AND so a
  /// concurrent [drainOnce] (next timer tick fires while the previous drain
  /// is still dispatching) skips re-entry. Without the latter, two drains
  /// would `peekPending` the same rows and the dual `markFailed` writes
  /// (read-then-write on `attempts`) would double-increment the retry
  /// counter, dead-lettering rows after `deadLetterAfter / 2` real failures.
  Future<void>? _inFlightDrain;

  /// Default dispatcher backed by the real Supabase client.
  static OutboxDispatch supabaseDispatcher(SupabaseClient client) {
    return (forTable, op, rowId, payload) async {
      final table = client.from(forTable);
      switch (op) {
        case 'insert':
          await table.insert(payload);
          break;
        case 'update':
          await table.update(payload).eq('id', rowId);
          break;
        case 'delete':
          await table.delete().eq('id', rowId);
          break;
        default:
          throw StateError('OutboxWorker: unknown op "$op"');
      }
    };
  }

  /// Pump one batch of pending mutations. Returns the count successfully sent.
  /// Stops on the first failure to avoid hammering a flaky backend.
  Future<int> drainOnce() {
    if (_inFlightDrain != null) return Future.value(0);
    final work = _drainOnce();
    _inFlightDrain = work.then(
      (_) => _inFlightDrain = null,
      onError: (Object _) => _inFlightDrain = null,
    );
    return work;
  }

  Future<int> _drainOnce() async {
    final batch = await repo.peekPending(limit: batchSize);
    var sent = 0;
    for (final row in batch) {
      try {
        final payload = jsonDecode(row.payloadJson) as Map<String, dynamic>;
        await dispatch(row.forTable, row.op, row.rowId, payload);
        await repo.markSent(row.id);
        sent++;
      } on PostgrestException catch (e) {
        await repo.markFailed(row.id, '${e.code ?? ''}: ${e.message}',
            deadLetterAfter: deadLetterAfter);
        return sent;
      } catch (e) {
        if (isTransientSyncError(e) && !(isOnline?.call() ?? false)) {
          // Offline (or connectivity unknown): a whole-device transport blip,
          // not this row's fault. Leave it pending and stop this drain; the
          // next cycle retries WITHOUT burning the dead-letter budget. Keeps a
          // flaky-signal rider from accumulating false sync errors.
          return sent;
        }
        // Either a permanent error, or a transient-looking error while the
        // device IS online — which makes it row-specific. Count it toward the
        // dead-letter budget so one persistently-failing head row can't
        // head-of-line block the rest of the queue indefinitely.
        await repo.markFailed(row.id, e.toString(),
            deadLetterAfter: deadLetterAfter);
        return sent;
      }
    }
    return sent;
  }

  /// Start a periodic drain (default 5s). Cancel with `stop()`.
  void start({Duration interval = const Duration(seconds: 5)}) {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => drainOnce());
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    final inflight = _inFlightDrain;
    if (inflight != null) await inflight;
  }
}
