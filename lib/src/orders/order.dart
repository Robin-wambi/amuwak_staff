import '../data/app_database.dart' as drift;
import 'order_status.dart';
import 'proof_event.dart';
import 'service_type.dart';

class LaundryOrder {
  const LaundryOrder({
    required this.orderId,
    required this.customerName,
    required this.serviceType,
    required this.status,
    required this.timeLabel,
    required this.itemCount,
    required this.phone,
    required this.address,
    required this.notes,
    this.proofEvents = const [],
  });

  final String orderId;
  final String customerName;
  final ServiceType serviceType;
  final OrderStatus status;
  final String timeLabel;
  final int itemCount;
  final String phone;
  final String address;
  final String notes;
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
  /// `proof_events` rows.
  ///
  /// Postgres has six order-status strings; the UI enum has four. `received`
  /// folds into `inProgress` and `out_for_delivery` folds into
  /// `readyForDelivery` — TODO(plan-3b-status-chips): split these out once
  /// the dashboard chip set is expanded.
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
      customerName: row.customerName,
      serviceType: ServiceType.fromDbString(row.serviceType),
      status: _statusFromString(row.status),
      timeLabel: _formatTime(row.scheduledFor ?? row.createdAt),
      itemCount: row.itemCount,
      phone: row.phone,
      address: row.address,
      notes: row.notes,
      proofEvents: events
          .map((e) => ProofEvent(
                id: e.id,
                type: _proofTypeFromString(e.type),
                capturedAt: e.capturedAt,
                count: e.itemCount,
                photoPaths: const [],
                notes: e.notes,
              ))
          .toList(growable: false),
    );
  }

  static OrderStatus _statusFromString(String s) => switch (s) {
        'pending_pickup' => OrderStatus.pendingPickup,
        'received' || 'in_progress' => OrderStatus.inProgress,
        'ready' || 'out_for_delivery' => OrderStatus.readyForDelivery,
        'completed' => OrderStatus.completed,
        _ => throw StateError('Unknown order status: "$s"'),
      };

  static ProofEventType _proofTypeFromString(String s) => switch (s) {
        'pickup' => ProofEventType.pickup,
        'delivery' => ProofEventType.delivery,
        _ => throw StateError('Unknown proof event type: "$s"'),
      };

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

  LaundryOrder copyWith({
    String? orderId,
    String? customerName,
    ServiceType? serviceType,
    OrderStatus? status,
    String? timeLabel,
    int? itemCount,
    String? phone,
    String? address,
    String? notes,
    List<ProofEvent>? proofEvents,
  }) {
    return LaundryOrder(
      orderId: orderId ?? this.orderId,
      customerName: customerName ?? this.customerName,
      serviceType: serviceType ?? this.serviceType,
      status: status ?? this.status,
      timeLabel: timeLabel ?? this.timeLabel,
      itemCount: itemCount ?? this.itemCount,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      notes: notes ?? this.notes,
      proofEvents: proofEvents ?? this.proofEvents,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! LaundryOrder) return false;
    if (other.orderId != orderId ||
        other.customerName != customerName ||
        other.serviceType != serviceType ||
        other.status != status ||
        other.timeLabel != timeLabel ||
        other.itemCount != itemCount ||
        other.phone != phone ||
        other.address != address ||
        other.notes != notes) {
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
        customerName,
        serviceType,
        status,
        timeLabel,
        itemCount,
        phone,
        address,
        notes,
        Object.hashAll(proofEvents),
      );
}
