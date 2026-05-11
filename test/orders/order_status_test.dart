import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_staff/src/orders/order_status.dart';

void main() {
  group('OrderStatus', () {
    test('exposes a human-readable label for each status', () {
      expect(OrderStatus.pendingPickup.label, 'Pending pickup');
      expect(OrderStatus.inProgress.label, 'In progress');
      expect(OrderStatus.readyForDelivery.label, 'Ready for delivery');
      expect(OrderStatus.completed.label, 'Completed');
    });

    test('exposes the brand color for each status', () {
      expect(OrderStatus.pendingPickup.color, const Color(0xFF9A5B00));
      expect(OrderStatus.inProgress.color, const Color(0xFF7A4CC2));
      expect(OrderStatus.readyForDelivery.color, const Color(0xFF0B7285));
      expect(OrderStatus.completed.color, const Color(0xFF2F7D32));
    });

    test('nextStatus advances through the laundry pipeline', () {
      expect(OrderStatus.pendingPickup.nextStatus, OrderStatus.inProgress);
      expect(OrderStatus.inProgress.nextStatus, OrderStatus.readyForDelivery);
      expect(OrderStatus.readyForDelivery.nextStatus, OrderStatus.completed);
    });

    test('completed is terminal — nextStatus is null', () {
      expect(OrderStatus.completed.nextStatus, isNull);
    });
  });
}
