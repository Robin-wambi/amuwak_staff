import '../data/app_database.dart' as drift;
import 'order_status.dart';
import 'proof_event.dart';
import 'service_type.dart';

class LaundryOrder {
  const LaundryOrder({
    required this.orderId,
    String? orderCode,
    this.customerId,
    required this.customerName,
    required this.serviceType,
    required this.status,
    required this.timeLabel,
    required this.itemCount,
    required this.phone,
    required this.address,
    required this.notes,
    this.intakeMethod = 'driver_pickup',
    this.fulfillmentMethod = 'delivery',
    this.scheduledFor,
    this.proofEvents = const [],
  }) : orderCode = orderCode ?? orderId;

  final String orderId;
  final String orderCode;
  final String? customerId;
  final String customerName;
  final ServiceType serviceType;
  final OrderStatus status;
  final String timeLabel;
  final int itemCount;
  final String phone;
  final String address;
  final String notes;
  final String intakeMethod;
  final String fulfillmentMethod;
  final DateTime? scheduledFor;
  final List<ProofEvent> proofEvents;

  ProofEvent? get pickupProof => _firstOfType(ProofEventType.pickup);
  ProofEvent? get deliveryProof => _firstOfType(ProofEventType.delivery);
  bool get hasPickupProof => pickupProof != null;
  bool get hasDeliveryProof => deliveryProof != null;

  ProofEvent? _firstOfType(ProofEventType type) {
    for (final event in proofEvents) {
      if (event.type == type) return event;
    }
    return null;
  }

  /// Hydrates a [LaundryOrder] from a Drift `orders` row plus its joined
  /// `proof_events` rows. The six-to-four status folding and the unknown-value
  /// degrade live on [OrderStatus.fromDbString] / [ProofEventType.fromDbString].
  ///
  /// Photos are intentionally dropped here — `photoPaths` is always
  /// `const []` because the photo binaries live in Supabase Storage and
  /// aren't pulled to the device until Plan 4.
  factory LaundryOrder.fromDriftRow(
    drift.Order row,
    List<drift.ProofEvent> events,
  ) {
    return LaundryOrder(
      orderId: row.id,
      orderCode: row.orderCode,
      customerId: row.customerId,
      customerName: row.customerName,
      serviceType: ServiceType.fromDbString(row.serviceType),
      status: OrderStatus.fromDbString(row.status),
      timeLabel: computeTimeLabel(
        scheduledFor: row.scheduledFor,
      ),
      itemCount: row.itemCount,
      phone: row.phone,
      address: row.address,
      notes: row.notes,
      intakeMethod: row.intakeMethod,
      fulfillmentMethod: row.fulfillmentMethod,
      scheduledFor: row.scheduledFor,
      proofEvents: events
          .map((e) => ProofEvent(
                id: e.id,
                type: ProofEventType.fromDbString(e.type),
                capturedAt: e.capturedAt,
                count: e.itemCount,
                photoPaths: const [],
                notes: e.notes,
              ))
          .toList(growable: false),
    );
  }

  /// Hydrates a [LaundryOrder] from a Supabase `orders` row (snake_case JSON)
  /// plus its joined `proof_events` rows. The online-only read path's
  /// counterpart to [fromDriftRow] — same status/service folding and the same
  /// "photos live in Storage, drop them here" rule (`photoPaths` is `const []`).
  /// Soft-deleted proof rows (`deleted_at != null`) are dropped so they don't
  /// surface to the rider.
  factory LaundryOrder.fromSupabase(
    Map<String, dynamic> row,
    List<Map<String, dynamic>> proofRows,
  ) {
    final scheduledFor = row['scheduled_for'] == null
        ? null
        : DateTime.parse(row['scheduled_for'] as String);
    return LaundryOrder(
      orderId: row['id'] as String,
      orderCode: row['order_code'] as String?,
      customerId: row['customer_id'] as String?,
      customerName: row['customer_name'] as String,
      serviceType: ServiceType.fromDbString(row['service_type'] as String),
      status: OrderStatus.fromDbString(row['status'] as String),
      timeLabel: computeTimeLabel(
        scheduledFor: scheduledFor,
      ),
      itemCount: row['item_count'] as int,
      phone: row['phone'] as String,
      address: row['address'] as String,
      notes: (row['notes'] as String?) ?? '',
      intakeMethod: (row['intake_method'] as String?) ?? 'driver_pickup',
      fulfillmentMethod: (row['fulfillment_method'] as String?) ?? 'delivery',
      scheduledFor: scheduledFor,
      proofEvents: proofRows
          .where((e) => e['deleted_at'] == null)
          .map((e) => ProofEvent(
                id: e['id'] as String,
                type: ProofEventType.fromDbString(e['type'] as String),
                capturedAt: DateTime.parse(e['captured_at'] as String),
                count: e['item_count'] as int,
                photoPaths: const [],
                notes: e['notes'] as String?,
              ))
          .toList(growable: false),
    );
  }

  static String _formatTime(DateTime t) {
    final hour12 = switch (t.hour) {
      0 => 12,
      final h when h > 12 => h - 12,
      final h => h,
    };
    final minute = t.minute.toString().padLeft(2, '0');
    final ampm = t.hour < 12 ? 'AM' : 'PM';
    return '$hour12:$minute $ampm';
  }

  static const _weekdayShort = [
    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
  ];
  static const _monthShort = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// Human-readable label for a scheduled pickup/delivery time.
  /// Examples: `'Today, 2:15 PM'`, `'Tomorrow, 9:00 AM'`, `'Mon 1 Jun, 9:00 AM'`.
  /// The reference "now" is injectable for tests; defaults to [DateTime.now].
  static String formatScheduled(DateTime when, {DateTime Function()? now}) {
    final today = (now ?? DateTime.now)();
    final scheduledDay = DateTime(when.year, when.month, when.day);
    final todayDay = DateTime(today.year, today.month, today.day);
    final dayDelta = scheduledDay.difference(todayDay).inDays;
    final time = _formatTime(when);
    if (dayDelta == 0) return 'Today, $time';
    if (dayDelta == 1) return 'Tomorrow, $time';
    final weekday = _weekdayShort[when.weekday - 1];
    final month = _monthShort[when.month - 1];
    return '$weekday ${when.day} $month, $time';
  }

  /// Single source of truth for the `timeLabel` shown on the dashboard order
  /// card. Both [LaundryOrder.fromDriftRow] (when the stream re-emits an
  /// order after sync) and the New Pickup form (when it builds the in-memory
  /// `LaundryOrder` to pass to `upsertOrder`) call this so the displayed
  /// label can't drift between the in-memory and post-roundtrip values.
  ///
  /// - Scheduled orders → `'Today, 2:15 PM'` etc. via [formatScheduled].
  /// - Immediate orders → `'Pickup: now'` (a stable label that tells the
  ///   rider this order doesn't have a future schedule, distinct from the
  ///   creation timestamp which is shown elsewhere on the card).
  static String computeTimeLabel({
    required DateTime? scheduledFor,
    DateTime Function()? now,
  }) {
    if (scheduledFor != null) return formatScheduled(scheduledFor, now: now);
    return 'Pickup: now';
  }

  LaundryOrder copyWith({
    String? orderId,
    String? orderCode,
    String? customerId,
    String? customerName,
    ServiceType? serviceType,
    OrderStatus? status,
    String? timeLabel,
    int? itemCount,
    String? phone,
    String? address,
    String? notes,
    String? intakeMethod,
    String? fulfillmentMethod,
    DateTime? scheduledFor,
    bool clearCustomerId = false,
    bool clearScheduledFor = false,
    List<ProofEvent>? proofEvents,
  }) {
    return LaundryOrder(
      orderId: orderId ?? this.orderId,
      orderCode: orderCode ?? this.orderCode,
      customerId: clearCustomerId ? null : (customerId ?? this.customerId),
      customerName: customerName ?? this.customerName,
      serviceType: serviceType ?? this.serviceType,
      status: status ?? this.status,
      timeLabel: timeLabel ?? this.timeLabel,
      itemCount: itemCount ?? this.itemCount,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      notes: notes ?? this.notes,
      intakeMethod: intakeMethod ?? this.intakeMethod,
      fulfillmentMethod: fulfillmentMethod ?? this.fulfillmentMethod,
      scheduledFor:
          clearScheduledFor ? null : (scheduledFor ?? this.scheduledFor),
      proofEvents: proofEvents ?? this.proofEvents,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! LaundryOrder) return false;
    if (other.orderId != orderId ||
        other.orderCode != orderCode ||
        other.customerId != customerId ||
        other.customerName != customerName ||
        other.serviceType != serviceType ||
        other.status != status ||
        other.timeLabel != timeLabel ||
        other.itemCount != itemCount ||
        other.phone != phone ||
        other.address != address ||
        other.notes != notes ||
        other.intakeMethod != intakeMethod ||
        other.fulfillmentMethod != fulfillmentMethod ||
        other.scheduledFor != scheduledFor) {
      return false;
    }
    if (proofEvents.length != other.proofEvents.length) return false;
    for (var i = 0; i < proofEvents.length; i++) {
      if (proofEvents[i] != other.proofEvents[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        orderId,
        orderCode,
        customerId,
        customerName,
        serviceType,
        status,
        timeLabel,
        itemCount,
        phone,
        address,
        notes,
        intakeMethod,
        fulfillmentMethod,
        scheduledFor,
        Object.hashAll(proofEvents),
      );
}
