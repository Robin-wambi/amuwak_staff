import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_staff/src/data/app_database.dart' as drift;
import 'package:amuwak_staff/src/orders/order.dart';
import 'package:amuwak_staff/src/orders/order_status.dart';
import 'package:amuwak_staff/src/orders/proof_event.dart';

drift.Order _orderRow({
  String id = 'AMW-1024',
  String status = 'in_progress',
  DateTime? scheduledFor,
  DateTime? createdAt,
  String customerName = 'Sarah N.',
  String serviceType = 'Wash & Iron',
  int itemCount = 8,
  String phone = '+256 700 123 456',
  String address = 'Kikoni',
  String notes = '',
}) {
  final created = createdAt ?? DateTime.utc(2026, 5, 19, 10, 0);
  return drift.Order(
    id: id,
    orderCode: id,
    customerId: null,
    customerName: customerName,
    phone: phone,
    address: address,
    serviceType: serviceType,
    status: status,
    intakeMethod: 'driver_pickup',
    fulfillmentMethod: 'delivery',
    itemCount: itemCount,
    notes: notes,
    scheduledFor: scheduledFor,
    assignedDriver: null,
    intakeRecordedBy: 's-1',
    createdBy: 's-1',
    createdAt: created,
    updatedAt: created,
    deletedAt: null,
  );
}

drift.ProofEvent _proofRow({
  required String id,
  required String orderId,
  required String type,
  required DateTime capturedAt,
  int itemCount = 8,
  String? notes,
}) {
  return drift.ProofEvent(
    id: id,
    orderId: orderId,
    type: type,
    capturedAt: capturedAt,
    itemCount: itemCount,
    notes: notes,
    capturedBy: 's-1',
    createdAt: capturedAt,
    updatedAt: capturedAt,
    deletedAt: null,
  );
}

void main() {
  group('LaundryOrder.fromDriftRow', () {
    test('maps each Postgres status string to the matching OrderStatus enum', () {
      // Six Postgres statuses (pending_pickup, received, in_progress, ready,
      // out_for_delivery, completed) collapse to the UI's four enum values.
      // received → inProgress and out_for_delivery → readyForDelivery are
      // intentional aliases — see TODO in the mapper for the follow-up UI plan.
      final cases = <String, OrderStatus>{
        'pending_pickup': OrderStatus.pendingPickup,
        'received': OrderStatus.inProgress,
        'in_progress': OrderStatus.inProgress,
        'ready': OrderStatus.readyForDelivery,
        'out_for_delivery': OrderStatus.readyForDelivery,
        'completed': OrderStatus.completed,
      };
      cases.forEach((pgStatus, expected) {
        final row = _orderRow(status: pgStatus);
        final mapped = LaundryOrder.fromDriftRow(row, const []);
        expect(mapped.status, expected, reason: 'for "$pgStatus"');
      });
    });

    test('throws StateError for an unknown status string', () {
      final row = _orderRow(status: 'banana');
      expect(
        () => LaundryOrder.fromDriftRow(row, const []),
        throwsA(isA<StateError>()),
      );
    });

    test('uses scheduledFor when present for the timeLabel', () {
      final row = _orderRow(
        scheduledFor: DateTime(2026, 5, 19, 10, 30),
        createdAt: DateTime(2026, 5, 19, 8, 0),
      );
      final mapped = LaundryOrder.fromDriftRow(row, const []);
      expect(mapped.timeLabel, '10:30 AM');
    });

    test('falls back to createdAt when scheduledFor is null', () {
      final row = _orderRow(
        scheduledFor: null,
        createdAt: DateTime(2026, 5, 19, 14, 15),
      );
      final mapped = LaundryOrder.fromDriftRow(row, const []);
      expect(mapped.timeLabel, '2:15 PM');
    });

    test('formats midnight as 12:00 AM and noon as 12:00 PM', () {
      final midnight = LaundryOrder.fromDriftRow(
        _orderRow(scheduledFor: DateTime(2026, 5, 19, 0, 0)),
        const [],
      );
      expect(midnight.timeLabel, '12:00 AM');
      final noon = LaundryOrder.fromDriftRow(
        _orderRow(scheduledFor: DateTime(2026, 5, 19, 12, 0)),
        const [],
      );
      expect(noon.timeLabel, '12:00 PM');
    });

    test('maps two proof events of different types to domain ProofEvents '
        'with photoPaths: const [] (photos deferred to Plan 4)', () {
      final pickupAt = DateTime(2026, 5, 19, 10, 30);
      final deliveryAt = DateTime(2026, 5, 19, 16, 0);
      final row = _orderRow(id: 'AMW-1');
      final events = [
        _proofRow(
          id: 'pe-1',
          orderId: 'AMW-1',
          type: 'pickup',
          capturedAt: pickupAt,
          itemCount: 8,
          notes: 'Carefully bagged',
        ),
        _proofRow(
          id: 'pe-2',
          orderId: 'AMW-1',
          type: 'delivery',
          capturedAt: deliveryAt,
          itemCount: 8,
          notes: null,
        ),
      ];
      final mapped = LaundryOrder.fromDriftRow(row, events);
      expect(mapped.proofEvents, hasLength(2));
      expect(mapped.proofEvents[0].type, ProofEventType.pickup);
      expect(mapped.proofEvents[0].capturedAt, pickupAt);
      expect(mapped.proofEvents[0].count, 8);
      expect(mapped.proofEvents[0].notes, 'Carefully bagged');
      expect(mapped.proofEvents[0].photoPaths, const <String>[]);
      expect(mapped.proofEvents[1].type, ProofEventType.delivery);
      expect(mapped.proofEvents[1].notes, isNull);
      expect(mapped.proofEvents[1].photoPaths, const <String>[]);
    });

    test('returns a LaundryOrder with no proof events when given an empty list', () {
      final mapped = LaundryOrder.fromDriftRow(_orderRow(), const []);
      expect(mapped.proofEvents, isEmpty);
    });

    test('throws StateError for an unknown proof event type', () {
      final row = _orderRow(id: 'AMW-1');
      final events = [
        _proofRow(
          id: 'pe-1',
          orderId: 'AMW-1',
          type: 'banana',
          capturedAt: DateTime(2026, 5, 19, 10, 30),
        ),
      ];
      expect(
        () => LaundryOrder.fromDriftRow(row, events),
        throwsA(isA<StateError>()),
      );
    });

    test('copies the simple scalar fields onto LaundryOrder', () {
      final row = _orderRow(
        id: 'AMW-1027',
        customerName: 'Daniel M.',
        serviceType: 'Wash only',
        itemCount: 5,
        phone: '+256 703 333 222',
        address: 'Bwaise',
        notes: 'Paid in cash at pickup.',
      );
      final mapped = LaundryOrder.fromDriftRow(row, const []);
      expect(mapped.orderId, 'AMW-1027');
      expect(mapped.customerName, 'Daniel M.');
      expect(mapped.serviceType, 'Wash only');
      expect(mapped.itemCount, 5);
      expect(mapped.phone, '+256 703 333 222');
      expect(mapped.address, 'Bwaise');
      expect(mapped.notes, 'Paid in cash at pickup.');
    });
  });
}
