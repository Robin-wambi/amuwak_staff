import 'order.dart';
import 'order_status.dart';

/// The set of order subsets a dashboard summary card can drill into.
///
/// A single [OrderFilter] is the source of truth for BOTH a summary card's
/// count and the list shown on the screen the card opens, so the number on the
/// card can never disagree with the orders behind it.
enum OrderFilter {
  /// Every assigned order, regardless of status — the "Assigned" card.
  all,
  pendingPickup,
  inProgress,
  readyForDelivery,

  /// Orders *delivered today* (status completed + a delivery proof captured on
  /// the current calendar day). Distinct from an all-time completed count.
  completedToday;

  String get label => switch (this) {
        OrderFilter.all => 'Assigned',
        OrderFilter.pendingPickup => OrderStatus.pendingPickup.label,
        OrderFilter.inProgress => OrderStatus.inProgress.label,
        OrderFilter.readyForDelivery => OrderStatus.readyForDelivery.label,
        OrderFilter.completedToday => 'Completed today',
      };

  /// Completed work reads best most-recent-first; upcoming work reads best
  /// soonest-first. Only [completedToday] sorts newest-first.
  bool get newestFirst => this == OrderFilter.completedToday;

  bool matches(LaundryOrder o, {required DateTime now}) => switch (this) {
        OrderFilter.all => true,
        OrderFilter.pendingPickup => o.status == OrderStatus.pendingPickup,
        OrderFilter.inProgress => o.status == OrderStatus.inProgress,
        OrderFilter.readyForDelivery =>
          o.status == OrderStatus.readyForDelivery,
        OrderFilter.completedToday => _isCompletedToday(o, now),
      };

  List<LaundryOrder> apply(
    List<LaundryOrder> orders, {
    DateTime Function()? now,
  }) {
    final reference = (now ?? DateTime.now)();
    return orders
        .where((o) => matches(o, now: reference))
        .toList(growable: false);
  }

  static bool _isCompletedToday(LaundryOrder o, DateTime now) {
    if (o.status != OrderStatus.completed) return false;
    final delivered = o.deliveryProof?.capturedAt;
    if (delivered == null) return false;
    return delivered.year == now.year &&
        delivered.month == now.month &&
        delivered.day == now.day;
  }
}
