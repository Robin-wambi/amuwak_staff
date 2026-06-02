import '../data/app_database.dart';

/// Pure JSON → Drift-data-class mappers for the ONLINE read path.
///
/// In online-only mode the repositories read straight from Supabase and hand
/// back the same Drift data classes the screens already consume (so no UI
/// changes). These mirror the column shapes of the SyncPuller's
/// JSON → Companion mappers (see `sync_puller.dart`), but build the immutable
/// data classes directly instead of going through the local database.
///
/// Supabase returns snake_case keys; the Drift data classes use camelCase
/// Dart fields. Keep the key strings here in sync with the table definitions
/// under `lib/src/data/tables/`.
///
/// NB: `LaundryOrder.fromSupabase` lives on the domain model in
/// `lib/src/orders/order.dart` (it folds the joined proof events into the
/// domain `ProofEvent`, which collides by name with the Drift `ProofEvent`
/// imported here, so it can't live in this file).

DateTime _dt(Object? v) => DateTime.parse(v as String);
DateTime? _dtNullable(Object? v) => v == null ? null : DateTime.parse(v as String);

Customer customerFromSupabase(Map<String, dynamic> r) => Customer(
      id: r['id'] as String,
      name: r['name'] as String,
      phone: r['phone'] as String,
      address: r['address'] as String?,
      notes: r['notes'] as String?,
      createdAt: _dt(r['created_at']),
      updatedAt: _dt(r['updated_at']),
      deletedAt: _dtNullable(r['deleted_at']),
    );

StaffData staffFromSupabase(Map<String, dynamic> r) => StaffData(
      id: r['id'] as String,
      username: r['username'] as String,
      displayName: r['display_name'] as String,
      phone: r['phone'] as String?,
      role: r['role'] as String,
      active: r['active'] as bool? ?? true,
      mustChangePin: r['must_change_pin'] as bool? ?? false,
      createdAt: _dt(r['created_at']),
      updatedAt: _dt(r['updated_at']),
      deletedAt: _dtNullable(r['deleted_at']),
    );

OrderStatusEvent orderStatusEventFromSupabase(Map<String, dynamic> r) =>
    OrderStatusEvent(
      id: r['id'] as String,
      orderId: r['order_id'] as String,
      fromStatus: r['from_status'] as String?,
      toStatus: r['to_status'] as String,
      changedBy: r['changed_by'] as String,
      changedAt: _dt(r['changed_at']),
      source: r['source'] as String,
      deviceEventId: r['device_event_id'] as String?,
    );

/// Maps a `proof_events` row into the Drift [ProofEvent] data class returned by
/// `ProofEventsRepository.watchByOrder`.
ProofEvent proofEventRowFromSupabase(Map<String, dynamic> r) => ProofEvent(
      id: r['id'] as String,
      orderId: r['order_id'] as String,
      type: r['type'] as String,
      capturedAt: _dt(r['captured_at']),
      itemCount: r['item_count'] as int,
      notes: r['notes'] as String?,
      capturedBy: r['captured_by'] as String,
      createdAt: _dt(r['created_at']),
      updatedAt: _dt(r['updated_at']),
      deletedAt: _dtNullable(r['deleted_at']),
    );
