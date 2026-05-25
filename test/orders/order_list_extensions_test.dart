import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_staff/src/orders/order.dart';
import 'package:amuwak_staff/src/orders/order_list_extensions.dart';
import 'package:amuwak_staff/src/orders/order_status.dart';
import 'package:amuwak_staff/src/orders/service_type.dart';

LaundryOrder _orderWith(OrderStatus status, {int items = 1}) {
  return LaundryOrder(
    orderId: 'X',
    customerName: 'X',
    serviceType: ServiceType.washOnly,
    status: status,
    timeLabel: 'X',
    itemCount: items,
    phone: 'X',
    address: 'X',
    notes: 'X',
  );
}

void main() {
  group('OrderListStats', () {
    test('countByStatus returns the count for the given status', () {
      final orders = [
        _orderWith(OrderStatus.pendingPickup),
        _orderWith(OrderStatus.pendingPickup),
        _orderWith(OrderStatus.completed),
      ];

      expect(orders.countByStatus(OrderStatus.pendingPickup), 2);
      expect(orders.countByStatus(OrderStatus.inProgress), 0);
      expect(orders.countByStatus(OrderStatus.completed), 1);
    });

    test('totalItems sums itemCount across all orders', () {
      final orders = [
        _orderWith(OrderStatus.pendingPickup, items: 3),
        _orderWith(OrderStatus.completed, items: 5),
      ];

      expect(orders.totalItems, 8);
    });

    test('totalItems is 0 for an empty list', () {
      expect(<LaundryOrder>[].totalItems, 0);
    });
  });
}
