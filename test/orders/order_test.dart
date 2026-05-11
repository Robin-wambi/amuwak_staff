import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_staff/src/orders/order.dart';
import 'package:amuwak_staff/src/orders/order_status.dart';

void main() {
  const a = LaundryOrder(
    orderId: 'AMW-1',
    customerName: 'A',
    serviceType: 'Wash',
    status: OrderStatus.pendingPickup,
    timeLabel: 't',
    itemCount: 1,
    phone: 'p',
    address: 'addr',
    notes: 'n',
  );

  test('two LaundryOrders with the same fields are equal', () {
    const b = LaundryOrder(
      orderId: 'AMW-1',
      customerName: 'A',
      serviceType: 'Wash',
      status: OrderStatus.pendingPickup,
      timeLabel: 't',
      itemCount: 1,
      phone: 'p',
      address: 'addr',
      notes: 'n',
    );

    expect(a, equals(b));
    expect(a.hashCode, equals(b.hashCode));
  });

  test('copyWith with a new status produces a non-equal order', () {
    final updated = a.copyWith(status: OrderStatus.inProgress);

    expect(updated, isNot(equals(a)));
  });
}
