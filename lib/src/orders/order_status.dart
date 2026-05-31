import 'package:flutter/material.dart';

import '../shared/theme/status_colors.dart';

enum OrderStatus {
  pendingPickup(label: 'Pending pickup'),
  inProgress(label: 'In progress'),
  readyForDelivery(label: 'Ready for delivery'),
  completed(label: 'Completed');

  const OrderStatus({required this.label});

  final String label;

  /// Deprecated — use `Theme.of(context).extension<StatusColors>()!.of(status)`
  /// instead. Removed in Task 7 when screens are migrated to the theme extension.
  @Deprecated('Use StatusColors theme extension. Removed in Task 7.')
  Color get color => StatusColors.light.of(this).color;

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
