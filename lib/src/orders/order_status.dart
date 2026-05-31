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

  OrderStatus? get nextStatus => switch (this) {
        OrderStatus.pendingPickup => OrderStatus.inProgress,
        OrderStatus.inProgress => OrderStatus.readyForDelivery,
        OrderStatus.readyForDelivery => OrderStatus.completed,
        OrderStatus.completed => null,
      };
}
