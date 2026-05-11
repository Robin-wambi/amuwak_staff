import 'package:flutter/material.dart';

enum OrderStatus {
  pendingPickup(
    label: 'Pending pickup',
    color: Color(0xFF9A5B00),
  ),
  inProgress(
    label: 'In progress',
    color: Color(0xFF7A4CC2),
  ),
  readyForDelivery(
    label: 'Ready for delivery',
    color: Color(0xFF0B7285),
  ),
  completed(
    label: 'Completed',
    color: Color(0xFF2F7D32),
  );

  const OrderStatus({required this.label, required this.color});

  final String label;
  final Color color;

  OrderStatus? get nextStatus {
    switch (this) {
      case OrderStatus.pendingPickup:
        return OrderStatus.inProgress;
      case OrderStatus.inProgress:
        return OrderStatus.readyForDelivery;
      case OrderStatus.readyForDelivery:
        return OrderStatus.completed;
      case OrderStatus.completed:
        return null;
    }
  }
}
