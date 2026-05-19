import 'dart:async';
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'outbox_repository.dart';

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
    this.batchSize = 25,
    this.deadLetterAfter = 5,
  });

  final OutboxRepository repo;
  final OutboxDispatch dispatch;
  final int batchSize;

  /// After this many failed attempts the row is parked in `dead_letter`
  /// status so it stops blocking later mutations. A separate UI / admin
  /// flow surfaces dead-lettered rows for manual review.
  final int deadLetterAfter;

  Timer? _timer;

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
  Future<int> drainOnce() async {
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

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
