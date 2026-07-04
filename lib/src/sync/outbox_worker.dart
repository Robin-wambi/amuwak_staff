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
    required this.isOnline,
    this.batchSize = 25,
    this.deadLetterAfter = 5,
  });

  final OutboxRepository repo;
  final OutboxDispatch dispatch;

  /// Reports whether the device currently has connectivity. Used to tell an
  /// offline blip (skip without penalty) apart from an online, row-specific
  /// transient failure (must count toward the dead-letter budget so a poison
  /// head row can't block the queue forever).
  ///
  /// Required so the offline-vs-online decision is always an explicit caller
  /// choice. A caller with no real signal should pass `() => false` ("assume
  /// offline") — the fail-safe that never turns a flaky-signal rider's good
  /// writes into false errors — but must opt into it deliberately rather than
  /// inherit it from a forgotten parameter, which would silently reintroduce
  /// unbounded head-of-line blocking for transient errors.
  final bool Function() isOnline;

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
  ///
  /// The `rpc` op calls a Postgres function ([forTable] is the function name,
  /// [payload] the params) instead of a table write — used for `create_pickup`,
  /// which a rider cannot do as a direct `orders`/`customers` insert under RLS.
  /// The RPC is idempotent server-side and the real minted `order_code` is
  /// reconciled onto the local placeholder row by the puller (it pulls the now-
  /// synced server row), so the dispatcher does not need the RPC's return value.
  static OutboxDispatch supabaseDispatcher(SupabaseClient client) {
    return (forTable, op, rowId, payload) async {
      switch (op) {
        case 'insert':
          await client.from(forTable).insert(payload);
          break;
        case 'update':
          await client.from(forTable).update(payload).eq('id', rowId);
          break;
        case 'delete':
          await client.from(forTable).delete().eq('id', rowId);
          break;
        case 'rpc':
          await client.rpc(forTable, params: payload);
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
        if (e.code == '23505') {
          // Unique-violation: the row is already on the server. This happens
          // when a prior attempt's INSERT succeeded but the client never got
          // the ack (network dropped after the write). Treat it as success so
          // we don't burn the dead-letter budget and surface a false sync
          // error for data that was actually saved.
          await repo.markSent(row.id);
          sent++;
          continue;
        }
        await repo.markFailed(row.id, '${e.code ?? ''}: ${e.message}',
            deadLetterAfter: deadLetterAfter);
        return sent;
      } catch (e) {
        if (isTransientSyncError(e) && !isOnline()) {
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
