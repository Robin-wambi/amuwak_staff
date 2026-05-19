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
  Future<int> pullTable(String name) async {
    final since = await _readWatermark(name);
    final rows = await fetch(name, since);
    if (rows.isEmpty) return 0;

    DateTime maxUpdated = since;
    await db.batch((batch) {
      for (final row in rows) {
        _upsertRow(batch, name, row);
        final u = DateTime.parse(row['updated_at'] as String);
        if (u.isAfter(maxUpdated)) maxUpdated = u;
      }
    });
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
      case 'order_status_events':
        batch.insert(db.orderStatusEvents, _statusEventsFromJson(row), mode: InsertMode.insertOrReplace);
        break;
      case 'proof_events':
        batch.insert(db.proofEvents, _proofEventsFromJson(row), mode: InsertMode.insertOrReplace);
        break;
      case 'proof_photos':
        batch.insert(db.proofPhotos, _proofPhotosFromJson(row), mode: InsertMode.insertOrReplace);
        break;
      case 'issues':
        batch.insert(db.issues, _issuesFromJson(row), mode: InsertMode.insertOrReplace);
        break;
      case 'shifts':
        batch.insert(db.shifts, _shiftsFromJson(row), mode: InsertMode.insertOrReplace);
        break;
      case 'valid_transitions':
        batch.insert(db.validTransitions, _validTransitionsFromJson(row), mode: InsertMode.insertOrReplace);
        break;
      default:
        throw StateError('SyncPuller has no upsert mapper for table "$table"');
    }
  }

  // ------------- per-table JSON → Drift Companion mappers -------------

  DateTime _dt(Object? v) => DateTime.parse(v as String);
  DateTime? _dtNullable(Object? v) => v == null ? null : DateTime.parse(v as String);
  double? _doubleNullable(Object? v) =>
      v == null ? null : (v is num ? v.toDouble() : double.parse(v.toString()));

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

  OrderStatusEventsCompanion _statusEventsFromJson(Map<String, dynamic> r) =>
      OrderStatusEventsCompanion.insert(
        id: r['id'] as String,
        orderId: r['order_id'] as String,
        fromStatus: Value(r['from_status'] as String?),
        toStatus: r['to_status'] as String,
        changedBy: r['changed_by'] as String,
        changedAt: _dt(r['changed_at']),
        source: r['source'] as String,
        deviceEventId: Value(r['device_event_id'] as String?),
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

  ProofPhotosCompanion _proofPhotosFromJson(Map<String, dynamic> r) =>
      ProofPhotosCompanion.insert(
        id: r['id'] as String,
        proofEventId: r['proof_event_id'] as String,
        storagePath: r['storage_path'] as String,
        width: Value(r['width'] as int?),
        height: Value(r['height'] as int?),
        bytes: Value(r['bytes'] as int?),
        uploadedAt: Value(_dtNullable(r['uploaded_at'])),
        createdAt: _dt(r['created_at']),
      );

  IssuesCompanion _issuesFromJson(Map<String, dynamic> r) =>
      IssuesCompanion.insert(
        id: r['id'] as String,
        orderId: Value(r['order_id'] as String?),
        kind: r['kind'] as String,
        description: r['description'] as String,
        reportedBy: r['reported_by'] as String,
        reportedAt: _dt(r['reported_at']),
        resolvedAt: Value(_dtNullable(r['resolved_at'])),
        resolvedBy: Value(r['resolved_by'] as String?),
      );

  ShiftsCompanion _shiftsFromJson(Map<String, dynamic> r) =>
      ShiftsCompanion.insert(
        id: r['id'] as String,
        staffId: r['staff_id'] as String,
        startedAt: _dt(r['started_at']),
        startedLat: Value(_doubleNullable(r['started_lat'])),
        startedLng: Value(_doubleNullable(r['started_lng'])),
        endedAt: Value(_dtNullable(r['ended_at'])),
        endedLat: Value(_doubleNullable(r['ended_lat'])),
        endedLng: Value(_doubleNullable(r['ended_lng'])),
      );

  ValidTransitionsCompanion _validTransitionsFromJson(Map<String, dynamic> r) =>
      ValidTransitionsCompanion.insert(
        id: r['id'] as String,
        intakeMethod: r['intake_method'] as String,
        fulfillmentMethod: r['fulfillment_method'] as String,
        fromStatus: Value(r['from_status'] as String?),
        toStatus: r['to_status'] as String,
      );
}
