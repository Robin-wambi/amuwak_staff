/// Declarative list of which Postgres tables to pull and how. The SyncPuller
/// loops over this list every sync cycle.
class SyncTable {
  const SyncTable({
    required this.name,
    this.pkColumn = 'id',
    this.watermarkColumn = 'updated_at',
  });
  final String name;
  final String pkColumn;

  /// JSON / Postgres column the puller compares against the per-table
  /// watermark in `sync_watermarks.last_synced_at`. Defaults to
  /// `updated_at`; override per table for append-only or static-seed
  /// tables (e.g. `changed_at` for `order_status_events`, `created_at`
  /// for `proof_photos`).
  final String watermarkColumn;
}

/// Tables the SyncPuller pulls incrementally on every cycle. Only tables
/// whose Postgres schema carries an `updated_at` column with a corresponding
/// BEFORE UPDATE trigger (Supabase migrations 0002, 0003, 0004, 0006) appear
/// here — the watermarked pull relies on `updated_at` advancing on every
/// row change.
///
/// Deliberately excluded:
///   - `order_status_events` (append-only, only `changed_at`) — every event is
///     pulled in the orders/proof_events bucket on next pull cycle since
///     those tables update too. A follow-up plan can switch this to use
///     `changed_at` once the puller supports per-table watermark columns.
///   - `proof_photos` — likewise mostly immutable; uses `created_at`. Will
///     be handled by the photo upload outbox in Plan 4.
///   - `issues` and `shifts` — currently have no `updated_at` column. Adding
///     one is a corrective migration in the issues/shifts UX plan.
///   - `valid_transitions` — static seed data with no `updated_at`; fetched
///     once at app bootstrap (Plan 3).
///   - `outbox`, `sync_watermarks` — local-only, never round-tripped.
const List<SyncTable> kSyncTables = [
  SyncTable(name: 'staff'),
  SyncTable(name: 'customers'),
  SyncTable(name: 'orders'),
  SyncTable(name: 'proof_events'),
];
