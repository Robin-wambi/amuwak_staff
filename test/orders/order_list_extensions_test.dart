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

const _searchBase = LaundryOrder(
  orderId: 'AMW-2026-0042',
  customerName: 'Jane Smith',
  serviceType: ServiceType.washOnly,
  status: OrderStatus.pendingPickup,
  timeLabel: 't',
  itemCount: 1,
  phone: '0700123456',
  address: '12 Kololo Road',
  notes: '',
);

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

  group('OrderListSearch.searchBy', () {
    final other = _searchBase.copyWith(
      orderId: 'AMW-2026-0099',
      orderCode: 'AMW-2026-0099',
      customerName: 'Bob Jones',
      phone: '0788999000',
      address: '5 Entebbe Lane',
    );
    final orders = [_searchBase, other];

    test('empty / whitespace query returns the full list unchanged', () {
      expect(orders.searchBy(''), orders);
      expect(orders.searchBy('   '), orders);
    });

    test('matches on order code (partial, case-insensitive)', () {
      expect(orders.searchBy('0042'), [_searchBase]);
      expect(orders.searchBy('amw-2026-0042'), [_searchBase]);
    });

    test('matches on customer name (partial, case-insensitive)', () {
      expect(orders.searchBy('jane'), [_searchBase]);
      expect(orders.searchBy('JONES'), [other]);
    });

    test('matches on phone', () {
      expect(orders.searchBy('0700'), [_searchBase]);
    });

    test('matches phone ignoring formatting (spaces, +, country code)', () {
      // Orders created via the pickup form store the raw, formatted phone the
      // rider typed. A rider searching types digits without the spacing, so the
      // match must compare digit-only forms, not raw substrings.
      final formatted = _searchBase.copyWith(phone: '+256 700 123 456');
      expect([formatted].searchBy('700123456'), [formatted]);
      expect([formatted].searchBy('256 700 123'), [formatted]);
    });

    test('matches on address (partial, case-insensitive)', () {
      expect(orders.searchBy('kololo'), [_searchBase]);
      expect(orders.searchBy('entebbe'), [other]);
    });

    test('returns empty when nothing matches', () {
      expect(orders.searchBy('zzz-no-match'), isEmpty);
    });
  });
}
