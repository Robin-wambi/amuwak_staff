import 'dart:developer' as developer;

enum OrderStatus {
  pendingPickup(label: 'Pending pickup'),
  inProgress(label: 'In progress'),
  readyForDelivery(label: 'Ready for delivery'),
  completed(label: 'Completed');

  const OrderStatus({required this.label});

  final String label;

  String toDbString() => switch (this) {
        OrderStatus.pendingPickup    => 'pending_pickup',
        OrderStatus.inProgress       => 'in_progress',
        OrderStatus.readyForDelivery => 'ready',
        OrderStatus.completed        => 'completed',
      };

  /// Maps a Postgres `orders.status` string to the UI enum.
  ///
  /// Postgres has six status strings; the UI enum has four. `received` folds
  /// into [inProgress] and `out_for_delivery` folds into [readyForDelivery] —
  /// TODO(plan-3b-status-chips): split these out once the dashboard chip set
  /// is expanded.
  ///
  /// Unlike `ServiceType.fromDbString`, an unknown value degrades to
  /// [pendingPickup] + a log rather than throwing: a status added server-side
  /// before this app is updated must NOT crash the whole orders stream (which
  /// would blank the rider's list and block all work). [pendingPickup] is the
  /// safest fallback — it shows the order without pushing it forward.
  static OrderStatus fromDbString(String s) => switch (s) {
        'pending_pickup' => OrderStatus.pendingPickup,
        'received' || 'in_progress' => OrderStatus.inProgress,
        'ready' || 'out_for_delivery' => OrderStatus.readyForDelivery,
        'completed' => OrderStatus.completed,
        _ => _degradeUnknown(s),
      };

  static OrderStatus _degradeUnknown(String s) {
    // Logged at WARNING (level 900), not the default level: a server status the
    // UI can't represent is operationally significant, not noise. In particular
    // a terminal state like "cancelled" degrades to pendingPickup and would
    // surface a cancelled order in the rider's ACTIVE list — ops should see
    // this. TODO(plan-3b-status-chips): add the missing enum values.
    developer.log(
      'Unrecognized order status "$s" — showing it as pendingPickup so the '
      'orders stream keeps working.',
      name: 'OrderStatus',
      level: 900,
    );
    return OrderStatus.pendingPickup;
  }

  OrderStatus? get nextStatus => switch (this) {
        OrderStatus.pendingPickup => OrderStatus.inProgress,
        OrderStatus.inProgress => OrderStatus.readyForDelivery,
        OrderStatus.readyForDelivery => OrderStatus.completed,
        OrderStatus.completed => null,
      };
}
