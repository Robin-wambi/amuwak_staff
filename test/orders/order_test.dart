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

  group('LaundryOrder new fields (Plan PR-B)', () {
    test('orderCode defaults to orderId when not specified', () {
      const o = LaundryOrder(
        orderId: 'AMW-X1',
        customerName: 'X',
        serviceType: ServiceType.washAndIron,
        status: OrderStatus.pendingPickup,
        timeLabel: 't',
        itemCount: 1,
        phone: 'p',
        address: 'a',
        notes: '',
      );
      expect(o.orderCode, 'AMW-X1');
    });

    test('orderCode can be set distinctly from orderId', () {
      const o = LaundryOrder(
        orderId: 'uuid-1',
        orderCode: 'AMW-123',
        customerName: 'X',
        serviceType: ServiceType.washAndIron,
        status: OrderStatus.pendingPickup,
        timeLabel: 't',
        itemCount: 1,
        phone: 'p',
        address: 'a',
        notes: '',
      );
      expect(o.orderCode, 'AMW-123');
      expect(o.orderId, 'uuid-1');
    });

    test('intakeMethod defaults to driver_pickup', () {
      const o = LaundryOrder(
        orderId: 'X',
        customerName: 'X',
        serviceType: ServiceType.washAndIron,
        status: OrderStatus.pendingPickup,
        timeLabel: 't',
        itemCount: 1,
        phone: 'p',
        address: 'a',
        notes: '',
      );
      expect(o.intakeMethod, 'driver_pickup');
    });

    test('fulfillmentMethod defaults to delivery', () {
      const o = LaundryOrder(
        orderId: 'X',
        customerName: 'X',
        serviceType: ServiceType.washAndIron,
        status: OrderStatus.pendingPickup,
        timeLabel: 't',
        itemCount: 1,
        phone: 'p',
        address: 'a',
        notes: '',
      );
      expect(o.fulfillmentMethod, 'delivery');
    });

    test('customerId and scheduledFor default to null', () {
      const o = LaundryOrder(
        orderId: 'X',
        customerName: 'X',
        serviceType: ServiceType.washAndIron,
        status: OrderStatus.pendingPickup,
        timeLabel: 't',
        itemCount: 1,
        phone: 'p',
        address: 'a',
        notes: '',
      );
      expect(o.customerId, isNull);
      expect(o.scheduledFor, isNull);
    });

    test('copyWith preserves new fields when omitted', () {
      final scheduled = DateTime(2026, 6, 1, 9);
      final o = LaundryOrder(
        orderId: 'uuid-1',
        orderCode: 'AMW-123',
        customerId: 'cust-1',
        customerName: 'X',
        serviceType: ServiceType.washAndIron,
        status: OrderStatus.pendingPickup,
        timeLabel: 't',
        itemCount: 1,
        phone: 'p',
        address: 'a',
        notes: '',
        intakeMethod: 'walk_in',
        fulfillmentMethod: 'walk_out',
        scheduledFor: scheduled,
      );
      final copy = o.copyWith(itemCount: 2);
      expect(copy.orderCode, 'AMW-123');
      expect(copy.customerId, 'cust-1');
      expect(copy.intakeMethod, 'walk_in');
      expect(copy.fulfillmentMethod, 'walk_out');
      expect(copy.scheduledFor, scheduled);
      expect(copy.itemCount, 2);
    });

    test('copyWith with clearScheduledFor: true nulls out scheduledFor', () {
      final o = LaundryOrder(
        orderId: 'X',
        customerName: 'X',
        serviceType: ServiceType.washAndIron,
        status: OrderStatus.pendingPickup,
        timeLabel: 't',
        itemCount: 1,
        phone: 'p',
        address: 'a',
        notes: '',
        scheduledFor: DateTime(2026, 6, 1, 9),
      );
      final cleared = o.copyWith(clearScheduledFor: true);
      expect(cleared.scheduledFor, isNull);
    });

    group('formatScheduled', () {
      DateTime fixedNow() => DateTime(2026, 5, 26, 10);

      test('uses "Today" when scheduled date matches now', () {
        expect(
          LaundryOrder.formatScheduled(DateTime(2026, 5, 26, 14, 15),
              now: fixedNow),
          'Today, 2:15 PM',
        );
      });

      test('uses "Tomorrow" when scheduled is the next day', () {
        expect(
          LaundryOrder.formatScheduled(DateTime(2026, 5, 27, 9, 0),
              now: fixedNow),
          'Tomorrow, 9:00 AM',
        );
      });

      test('uses weekday + month for dates further out', () {
        expect(
          LaundryOrder.formatScheduled(DateTime(2026, 6, 1, 9, 0),
              now: fixedNow),
          'Mon 1 Jun, 9:00 AM',
        );
      });
    });

    test('copyWith with clearCustomerId: true nulls out customerId', () {
      const o = LaundryOrder(
        orderId: 'X',
        customerId: 'cust-9',
        customerName: 'X',
        serviceType: ServiceType.washAndIron,
        status: OrderStatus.pendingPickup,
        timeLabel: 't',
        itemCount: 1,
        phone: 'p',
        address: 'a',
        notes: '',
      );
      final cleared = o.copyWith(clearCustomerId: true);
      expect(cleared.customerId, isNull);
    });

    test('equality includes the new fields', () {
      const base = LaundryOrder(
        orderId: 'X',
        customerName: 'X',
        serviceType: ServiceType.washAndIron,
        status: OrderStatus.pendingPickup,
        timeLabel: 't',
        itemCount: 1,
        phone: 'p',
        address: 'a',
        notes: '',
      );
      final withCode = base.copyWith();
      expect(withCode, equals(base));

      const differentCode = LaundryOrder(
        orderId: 'X',
        orderCode: 'AMW-OTHER',
        customerName: 'X',
        serviceType: ServiceType.washAndIron,
        status: OrderStatus.pendingPickup,
        timeLabel: 't',
        itemCount: 1,
        phone: 'p',
        address: 'a',
        notes: '',
      );
      expect(differentCode, isNot(equals(base)));
    });
  });
}
