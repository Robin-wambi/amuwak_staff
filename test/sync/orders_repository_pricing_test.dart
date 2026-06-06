import 'package:flutter_test/flutter_test.dart';
import 'package:amuwak_staff/src/orders/order.dart';
import 'package:amuwak_staff/src/orders/order_status.dart';
import 'package:amuwak_staff/src/orders/service_type.dart';
import 'package:amuwak_staff/src/sync/orders_repository.dart';

void main() {
  group('OrdersRepository pricing', () {
    test('recomputeOrderTotal overwrites a stale caller total', () {
      final stale = LaundryOrder(
        orderId: 'o1',
        customerName: 'A',
        serviceType: ServiceType.washOnly,
        status: OrderStatus.pendingPickup,
        timeLabel: 'Pickup: now',
        itemCount: 0,
        phone: 'p',
        address: 'a',
        notes: '',
        ratePerKgSnapshotUgx: 5000,
        finalWeightKg: 4,
        totalUgx: 999999, // deliberately wrong
      );
      final corrected = OrdersRepository.recomputeOrderTotal(stale);
      expect(corrected.totalUgx, 20000); // 4 * 5000
    });

    test('resolveRatePerKg prefers the customer override', () {
      expect(
        OrdersRepository.resolveRatePerKg(
            customRate: 4000, defaultRate: 5000),
        4000,
      );
    });

    test('resolveRatePerKg falls back to the default when no override', () {
      expect(
        OrdersRepository.resolveRatePerKg(
            customRate: null, defaultRate: 5000),
        5000,
      );
    });
  });
}
