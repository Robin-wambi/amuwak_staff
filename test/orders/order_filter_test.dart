import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_staff/src/orders/order.dart';
import 'package:amuwak_staff/src/orders/order_filter.dart';
import 'package:amuwak_staff/src/orders/order_list_extensions.dart';
import 'package:amuwak_staff/src/orders/order_status.dart';
import 'package:amuwak_staff/src/orders/proof_event.dart';
import 'package:amuwak_staff/src/orders/service_type.dart';

LaundryOrder _order(
  OrderStatus status, {
  String id = 'X',
  DateTime? deliveredAt,
}) {
  return LaundryOrder(
    orderId: id,
    customerName: 'X',
    serviceType: ServiceType.washOnly,
    status: status,
    timeLabel: 't',
    itemCount: 1,
    phone: 'p',
    address: 'a',
    notes: '',
    proofEvents: deliveredAt == null
        ? const []
        : [
            ProofEvent(
              id: 'd-$id',
              type: ProofEventType.delivery,
              capturedAt: deliveredAt,
              count: 1,
              photoPaths: const [],
            ),
          ],
  );
}

void main() {
  // 11 Jun 2026, mid-morning.
  DateTime now() => DateTime(2026, 6, 11, 10);

  group('OrderFilter.apply', () {
    final orders = [
      _order(OrderStatus.pendingPickup),
      _order(OrderStatus.pendingPickup),
      _order(OrderStatus.inProgress),
      _order(OrderStatus.readyForDelivery),
      _order(OrderStatus.completed, deliveredAt: DateTime(2026, 6, 11, 9)),
    ];

    test('all returns every order (parity with list.length)', () {
      expect(OrderFilter.all.apply(orders, now: now).length, orders.length);
    });

    test('status filters match countByStatus', () {
      expect(
        OrderFilter.pendingPickup.apply(orders, now: now).length,
        orders.countByStatus(OrderStatus.pendingPickup),
      );
      expect(
        OrderFilter.inProgress.apply(orders, now: now).length,
        orders.countByStatus(OrderStatus.inProgress),
      );
      expect(
        OrderFilter.readyForDelivery.apply(orders, now: now).length,
        orders.countByStatus(OrderStatus.readyForDelivery),
      );
    });
  });

  group('OrderFilter.completedToday', () {
    test('includes an order delivered late today', () {
      final o = _order(OrderStatus.completed,
          deliveredAt: DateTime(2026, 6, 11, 23, 59));
      expect(OrderFilter.completedToday.matches(o, now: now()), isTrue);
    });

    test('excludes an order delivered just before midnight yesterday', () {
      final o = _order(OrderStatus.completed,
          deliveredAt: DateTime(2026, 6, 10, 23, 59));
      expect(OrderFilter.completedToday.matches(o, now: now()), isFalse);
    });

    test('excludes a completed order with no delivery proof', () {
      final o = _order(OrderStatus.completed);
      expect(OrderFilter.completedToday.matches(o, now: now()), isFalse);
    });

    test('excludes a non-completed order even with a delivery proof today', () {
      final o = _order(OrderStatus.readyForDelivery,
          deliveredAt: DateTime(2026, 6, 11, 9));
      expect(OrderFilter.completedToday.matches(o, now: now()), isFalse);
    });
  });

  group('OrderFilter labels and sort direction', () {
    test('labels', () {
      expect(OrderFilter.all.label, 'Assigned');
      expect(OrderFilter.pendingPickup.label, OrderStatus.pendingPickup.label);
      expect(OrderFilter.inProgress.label, OrderStatus.inProgress.label);
      expect(
        OrderFilter.readyForDelivery.label,
        OrderStatus.readyForDelivery.label,
      );
      expect(OrderFilter.completedToday.label, 'Completed today');
    });

    test('newestFirst only for completedToday', () {
      expect(OrderFilter.completedToday.newestFirst, isTrue);
      expect(OrderFilter.all.newestFirst, isFalse);
      expect(OrderFilter.pendingPickup.newestFirst, isFalse);
      expect(OrderFilter.inProgress.newestFirst, isFalse);
      expect(OrderFilter.readyForDelivery.newestFirst, isFalse);
    });
  });
}
