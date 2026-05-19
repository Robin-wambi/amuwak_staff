import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/app_database.dart';

class SyncStatus {
  const SyncStatus({
    required this.pendingCount,
    required this.lastSyncedAt,
    required this.online,
  });
  final int pendingCount;
  final DateTime? lastSyncedAt;
  final bool online;
}

/// Singleton AppDatabase shared by repositories, the OutboxWorker, the
/// SyncPuller, and the banner widget. Plan 3 will wire this provider into the
/// app's startup so the same instance is reused everywhere.
final appDatabaseProvider = Provider<AppDatabase>((_) => AppDatabase());

/// Live count of pending + failed outbox rows. Watched via Drift's stream
/// API so the banner updates immediately when a row is enqueued, sent, or
/// marked failed.
final pendingOutboxCountProvider = StreamProvider<int>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final countExpr = db.outbox.id.count();
  final query = db.selectOnly(db.outbox)
    ..addColumns([countExpr])
    ..where(db.outbox.status.isIn(<String>['pending', 'failed']));
  return query.watch().map((rows) => rows.first.read(countExpr) ?? 0);
});

/// Set by ConnectivityWatcher at app bootstrap (Plan 3 wiring).
final onlineProvider = StateProvider<bool>((_) => true);

/// Combined sync-status snapshot for the banner widget to consume.
final syncStatusProvider = Provider<SyncStatus>((ref) {
  final pending = ref.watch(pendingOutboxCountProvider).valueOrNull ?? 0;
  final online = ref.watch(onlineProvider);
  return SyncStatus(pendingCount: pending, lastSyncedAt: null, online: online);
});
