import 'package:flutter_test/flutter_test.dart';
import 'package:amuwak_staff/src/orders/order.dart';
import 'package:amuwak_staff/src/orders/pricing/line_item.dart';
import 'package:amuwak_staff/src/orders/order_status.dart';
import 'package:amuwak_staff/src/orders/service_type.dart';

LaundryOrder _base() => LaundryOrder(
      orderId: 'o1',
      customerName: 'Aisha',
      serviceType: ServiceType.washAndIron,
      status: OrderStatus.pendingPickup,
      timeLabel: 'Pickup: now',
      itemCount: 0,
      phone: '+256 700000000',
      address: 'Kampala',
      notes: '',
      ratePerKgSnapshotUgx: 5000,
    );

void main() {
  group('LaundryOrder pricing', () {
    test('defaults: no weights, empty line items, zero adjustment/total', () {
      final o = _base();
      expect(o.estimatedWeightKg, isNull);
      expect(o.finalWeightKg, isNull);
      expect(o.lineItems, isEmpty);
      expect(o.manualAdjustmentUgx, 0);
      expect(o.totalUgx, 0);
      expect(o.ratePerKgSnapshotUgx, 5000);
    });

    test('copyWith updates pricing fields and keeps the rest', () {
      final o = _base().copyWith(
        estimatedWeightKg: 3,
        lineItems: [LineItem(name: 'Blanket', amountUgx: 8000)],
        manualAdjustmentUgx: -1000,
        totalUgx: 22000,
      );
      expect(o.estimatedWeightKg, 3);
      expect(o.lineItems.single.name, 'Blanket');
      expect(o.manualAdjustmentUgx, -1000);
      expect(o.totalUgx, 22000);
      expect(o.customerName, 'Aisha');
    });

    test('fromSupabase reads pricing columns including jsonb line_items', () {
      final o = LaundryOrder.fromSupabase({
        'id': 'o2',
        'order_code': 'AMW-2026-0002',
        'customer_id': null,
        'customer_name': 'Bob',
        'phone': '+256 700000001',
        'address': 'Jinja',
        'service_type': 'Wash only',
        'status': 'pending_pickup',
        'item_count': 0,
        'notes': null,
        'scheduled_for': null,
        'rate_per_kg_snapshot_ugx': 5000,
        'estimated_weight_kg': 2.5,
        'final_weight_kg': null,
        'line_items': [
          {'name': 'Jacket', 'amount_ugx': 5000},
        ],
        'manual_adjustment_ugx': 0,
        'total_ugx': 17500,
      }, const []);
      expect(o.ratePerKgSnapshotUgx, 5000);
      expect(o.estimatedWeightKg, 2.5);
      expect(o.finalWeightKg, isNull);
      expect(o.lineItems.single.name, 'Jacket');
      expect(o.totalUgx, 17500);
    });

    test('fromSupabase tolerates a missing rate snapshot (degrades to 0)', () {
      // A row from a DB where migration 0019 has not yet added/backfilled the
      // pricing columns: the snapshot key is absent. One such row must not take
      // down the whole orders stream — degrade to 0 instead of throwing.
      final o = LaundryOrder.fromSupabase({
        'id': 'o3',
        'order_code': 'AMW-2026-0003',
        'customer_id': null,
        'customer_name': 'Carol',
        'phone': '+256 700000002',
        'address': 'Mbarara',
        'service_type': 'Wash only',
        'status': 'pending_pickup',
        'item_count': 0,
        'notes': null,
        'scheduled_for': null,
      }, const []);
      expect(o.ratePerKgSnapshotUgx, 0);
    });

    test('fromSupabase tolerates an explicit null rate snapshot (degrades to 0)',
        () {
      // Distinct from the absent-key case above: a present-but-null column must
      // also degrade to 0, so a future change can't regress one path silently.
      final o = LaundryOrder.fromSupabase({
        'id': 'o4',
        'order_code': 'AMW-2026-0004',
        'customer_id': null,
        'customer_name': 'Dan',
        'phone': '+256 700000003',
        'address': 'Gulu',
        'service_type': 'Wash only',
        'status': 'pending_pickup',
        'item_count': 0,
        'notes': null,
        'scheduled_for': null,
        'rate_per_kg_snapshot_ugx': null,
      }, const []);
      expect(o.ratePerKgSnapshotUgx, 0);
    });

    test('equality includes pricing fields', () {
      expect(_base().copyWith(totalUgx: 1) == _base(), isFalse);
    });
  });
}
