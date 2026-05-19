import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/app_database.dart';
import 'sync_registry.dart';

/// Fetches Postgres rows for [forTable] whose `updated_at` is strictly newer
/// than [since]. Implementations throw on failure; the puller stops the
/// affected table for this cycle and tries again next cycle.
typedef SyncFetch = Future<List<Map<String, dynamic>>> Function(
  String forTable,
  DateTime since,
);

/// Pulls Postgres rows that changed since a per-table watermark and upserts
/// them into the local Drift database. Used by the periodic puller and on
/// reconnect.
class SyncPuller {
  SyncPuller({required this.db, required this.fetch});

  final AppDatabase db;
  final SyncFetch fetch;

  static final DateTime _epoch = DateTime.utc(1970);

  /// Default fetcher backed by the real Supabase client.
  static SyncFetch supabaseFetcher(SupabaseClient client) {
    return (forTable, since) async {
      final List<dynamic> rows = await client
          .from(forTable)
          .select()
          .gt('updated_at', since.toIso8601String())
          .order('updated_at');
      return rows.cast<Map<String, dynamic>>().toList();
    };
  }

  Future<DateTime> _readWatermark(String forTable) async {
    final row = await (db.select(db.syncWatermarks)
          ..where((t) => t.forTable.equals(forTable)))
        .getSingleOrNull();
    return row?.lastSyncedAt ?? _epoch;
  }

  Future<void> _writeWatermark(String forTable, DateTime at) {
    return db.into(db.syncWatermarks).insertOnConflictUpdate(
          SyncWatermarksCompanion.insert(
            forTable: forTable,
            lastSyncedAt: at,
          ),
        );
  }

  /// Pull a single table. Returns the number of rows upserted.
  ///
  /// If any row in the batch fails to upsert (mapper exception, malformed
  /// timestamp, unhandled column, etc.), the entire batch is aborted and
  /// the watermark is **not** advanced — the cycle retries next time. This
  /// prevents the silent-data-loss path where a poison row poisons later
  /// rows in the batch while the watermark advances past all of them.
  Future<int> pullTable(String name) async {
    final since = await _readWatermark(name);
    final rows = await fetch(name, since);
    if (rows.isEmpty) return 0;

    DateTime maxUpdated = since;
    try {
      await db.batch((batch) {
        for (final row in rows) {
          _upsertRow(batch, name, row);
          final u = DateTime.parse(row['updated_at'] as String);
          if (u.isAfter(maxUpdated)) maxUpdated = u;
        }
      });
    } catch (e, st) {
      // ignore: avoid_print
      print('SyncPuller: batch for "$name" failed; watermark not advanced. $e\n$st');
      return 0;
    }
    await _writeWatermark(name, maxUpdated);
    return rows.length;
  }

  Future<int> pullAll() async {
    var total = 0;
    for (final t in kSyncTables) {
      total += await pullTable(t.name);
    }
    return total;
  }

  /// Switch is intentionally limited to the tables in [kSyncTables]. Any
  /// other table reaching this method is a bug — fall through to a
  /// StateError so it's visible immediately rather than silently dropped.
  /// Plan 3 / 4 will re-add cases (and corresponding mappers below) for
  /// `proof_photos`, `order_status_events`, `issues`, `shifts`, and
  /// `valid_transitions` once each has the right pull strategy.
  void _upsertRow(Batch batch, String table, Map<String, dynamic> row) {
    switch (table) {
      case 'staff':
        batch.insert(db.staff, _staffFromJson(row), mode: InsertMode.insertOrReplace);
        break;
      case 'customers':
        batch.insert(db.customers, _customersFromJson(row), mode: InsertMode.insertOrReplace);
        break;
      case 'orders':
        batch.insert(db.orders, _ordersFromJson(row), mode: InsertMode.insertOrReplace);
        break;
      case 'proof_events':
        batch.insert(db.proofEvents, _proofEventsFromJson(row), mode: InsertMode.insertOrReplace);
        break;
      default:
        throw StateError('SyncPuller has no upsert mapper for table "$table"');
    }
  }

  // ------------- per-table JSON → Drift Companion mappers -------------

  DateTime _dt(Object? v) => DateTime.parse(v as String);
  DateTime? _dtNullable(Object? v) => v == null ? null : DateTime.parse(v as String);

  StaffCompanion _staffFromJson(Map<String, dynamic> r) => StaffCompanion.insert(
        id: r['id'] as String,
        username: r['username'] as String,
        displayName: r['display_name'] as String,
        phone: Value(r['phone'] as String?),
        role: r['role'] as String,
        active: Value(r['active'] as bool? ?? true),
        mustChangePin: Value(r['must_change_pin'] as bool? ?? false),
        createdAt: _dt(r['created_at']),
        updatedAt: _dt(r['updated_at']),
        deletedAt: Value(_dtNullable(r['deleted_at'])),
      );

  CustomersCompanion _customersFromJson(Map<String, dynamic> r) => CustomersCompanion.insert(
        id: r['id'] as String,
        name: r['name'] as String,
        phone: r['phone'] as String,
        address: Value(r['address'] as String?),
        notes: Value(r['notes'] as String?),
        createdAt: _dt(r['created_at']),
        updatedAt: _dt(r['updated_at']),
        deletedAt: Value(_dtNullable(r['deleted_at'])),
      );

  OrdersCompanion _ordersFromJson(Map<String, dynamic> r) => OrdersCompanion.insert(
        id: r['id'] as String,
        orderCode: r['order_code'] as String,
        customerId: Value(r['customer_id'] as String?),
        customerName: r['customer_name'] as String,
        phone: r['phone'] as String,
        address: r['address'] as String,
        serviceType: r['service_type'] as String,
        status: r['status'] as String,
        intakeMethod: r['intake_method'] as String,
        fulfillmentMethod: r['fulfillment_method'] as String,
        itemCount: r['item_count'] as int,
        notes: Value(r['notes'] as String? ?? ''),
        scheduledFor: Value(_dtNullable(r['scheduled_for'])),
        assignedDriver: Value(r['assigned_driver'] as String?),
        intakeRecordedBy: r['intake_recorded_by'] as String,
        createdBy: r['created_by'] as String,
        createdAt: Value(_dt(r['created_at'])),
        updatedAt: Value(_dt(r['updated_at'])),
        deletedAt: Value(_dtNullable(r['deleted_at'])),
      );

  ProofEventsCompanion _proofEventsFromJson(Map<String, dynamic> r) =>
      ProofEventsCompanion.insert(
        id: r['id'] as String,
        orderId: r['order_id'] as String,
        type: r['type'] as String,
        capturedAt: _dt(r['captured_at']),
        itemCount: r['item_count'] as int,
        notes: Value(r['notes'] as String?),
        capturedBy: r['captured_by'] as String,
        createdAt: _dt(r['created_at']),
        updatedAt: _dt(r['updated_at']),
        deletedAt: Value(_dtNullable(r['deleted_at'])),
      );
}
