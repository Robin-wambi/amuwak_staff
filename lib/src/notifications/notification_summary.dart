import '../orders/order.dart';
import '../orders/order_status.dart';

/// How far back a delivered order stays in the summary feed.
const Duration kDeliveredWindow = Duration(hours: 48);

enum NotificationKind { newPickup, delivered }

/// One row in the Recent feed: an order plus why it is here.
class NotificationItem {
  const NotificationItem({required this.order, required this.kind});

  final LaundryOrder order;
  final NotificationKind kind;
}

/// Derived, read-only summary of the orders a rider cares about at a glance.
///
/// Pure: all filtering/sorting happens here from the in-memory orders list,
/// with [now] injected so it is deterministic under test. No I/O, no Flutter.
class NotificationSummary {
  const NotificationSummary({
    required this.newPickups,
    required this.delivered,
  });

  final List<LaundryOrder> newPickups;
  final List<LaundryOrder> delivered;

  factory NotificationSummary.fromOrders(
    List<LaundryOrder> orders, {
    required DateTime now,
  }) {
    final pickups = orders.where(_isNewPickup).toList()
      ..sort(_byScheduledForAscNullsLast);

    final cutoff = now.subtract(kDeliveredWindow);
    final delivered = orders.where((o) {
      // A still-pending order can't be "delivered" — guard against anomalous
      // data (a stray delivery proof on a pendingPickup order) listing the
      // same order in both the pickups and delivered feeds.
      if (_isNewPickup(o)) return false;
      final proof = o.deliveryProof;
      return proof != null && proof.capturedAt.isAfter(cutoff);
    }).toList()
      ..sort((a, b) =>
          b.deliveryProof!.capturedAt.compareTo(a.deliveryProof!.capturedAt));

    return NotificationSummary(newPickups: pickups, delivered: delivered);
  }

  /// Merged feed: pickups (imminent first) then delivered (most recent first).
  List<NotificationItem> get recent => [
        for (final o in newPickups)
          NotificationItem(order: o, kind: NotificationKind.newPickup),
        for (final o in delivered)
          NotificationItem(order: o, kind: NotificationKind.delivered),
      ];

  bool get isEmpty => newPickups.isEmpty && delivered.isEmpty;

  /// Single source of truth for "is this a new pickup" — shared by
  /// [fromOrders] and [pendingPickupCount] so the badge and the summary can't
  /// drift apart if the predicate ever changes.
  static bool _isNewPickup(LaundryOrder order) =>
      order.status == OrderStatus.pendingPickup;

  /// New-pickup count without building (and sorting) a whole summary — for the
  /// dashboard bell badge, which recomputes on every rebuild.
  static int pendingPickupCount(List<LaundryOrder> orders) =>
      orders.where(_isNewPickup).length;

  static int _byScheduledForAscNullsLast(LaundryOrder a, LaundryOrder b) {
    final sa = a.scheduledFor;
    final sb = b.scheduledFor;
    if (sa == null && sb == null) return a.orderCode.compareTo(b.orderCode);
    if (sa == null) return 1; // nulls last
    if (sb == null) return -1;
    final cmp = sa.compareTo(sb);
    return cmp != 0 ? cmp : a.orderCode.compareTo(b.orderCode);
  }
}
