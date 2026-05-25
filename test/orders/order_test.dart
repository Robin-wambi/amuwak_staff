import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_staff/src/orders/order.dart';
import 'package:amuwak_staff/src/orders/order_status.dart';
import 'package:amuwak_staff/src/orders/proof_event.dart';
import 'package:amuwak_staff/src/orders/service_type.dart';

void main() {
  const a = LaundryOrder(
    orderId: 'AMW-1',
    customerName: 'A',
    serviceType: ServiceType.washOnly,
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
      serviceType: ServiceType.washOnly,
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
    expect(updated.hashCode, isNot(equals(a.hashCode)));
  });

  group('LaundryOrder.proofEvents', () {
    final pickupEvent = ProofEvent(
      id: 'pe-test-1',
      type: ProofEventType.pickup,
      capturedAt: DateTime(2026, 5, 12, 9, 42),
      count: 12,
      photoPaths: const ['pickup_0.jpg'],
    );
    final deliveryEvent = ProofEvent(
      id: 'pe-test-2',
      type: ProofEventType.delivery,
      capturedAt: DateTime(2026, 5, 12, 16, 13),
      count: 12,
      photoPaths: const ['delivery_0.jpg'],
    );

    test('defaults to an empty list', () {
      expect(a.proofEvents, isEmpty);
      expect(a.hasPickupProof, isFalse);
      expect(a.hasDeliveryProof, isFalse);
      expect(a.pickupProof, isNull);
      expect(a.deliveryProof, isNull);
    });

    test('pickupProof returns the first pickup event', () {
      final order = a.copyWith(proofEvents: [pickupEvent, deliveryEvent]);

      expect(order.pickupProof, equals(pickupEvent));
      expect(order.hasPickupProof, isTrue);
    });

    test('deliveryProof returns the first delivery event', () {
      final order = a.copyWith(proofEvents: [pickupEvent, deliveryEvent]);

      expect(order.deliveryProof, equals(deliveryEvent));
      expect(order.hasDeliveryProof, isTrue);
    });

    test('value equality includes proofEvents', () {
      final withEvents = a.copyWith(proofEvents: [pickupEvent]);
      final withSameEvents = a.copyWith(proofEvents: [pickupEvent]);
      final withDifferentEvents = a.copyWith(proofEvents: [deliveryEvent]);

      expect(withEvents, equals(withSameEvents));
      expect(withEvents.hashCode, equals(withSameEvents.hashCode));
      expect(withEvents, isNot(equals(withDifferentEvents)));
    });

    test('copyWith preserves proofEvents when omitted', () {
      final original = a.copyWith(proofEvents: [pickupEvent]);
      final updated = original.copyWith(status: OrderStatus.inProgress);

      expect(updated.proofEvents, equals([pickupEvent]));
    });
  });
}
