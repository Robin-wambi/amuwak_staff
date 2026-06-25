import 'package:amuwak_staff/src/orders/order.dart';
import 'package:amuwak_staff/src/orders/order_status.dart';
import 'package:amuwak_staff/src/orders/service_type.dart';
import 'package:amuwak_staff/src/sync/orders_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// Unit-tests the id-scoped write methods through the [OrdersRepository.forTest]
/// seam: the dispatched column map (payload shape + audit pointers) and the
/// no-op [StateError] guard, without a live SupabaseClient. The pure payload
/// shapes are pinned separately in supabase_payloads_test.dart; here we verify
/// the repository wires the right id + payload and reacts to an empty result.
void main() {
  final clock = DateTime.utc(2026, 6, 24, 10, 30);

  LaundryOrder order({String id = 'o1'}) => LaundryOrder(
        orderId: id,
        orderCode: 'AMW-1',
        customerName: 'Ada',
        serviceType: ServiceType.washAndIron,
        status: OrderStatus.inProgress,
        timeLabel: 't',
        itemCount: 5,
        phone: '0700',
        address: 'Kira',
        notes: 'gate 4',
        scheduledFor: DateTime.utc(2026, 6, 25, 9),
        // Pricing snapshot that must never leak into a descriptive update.
        ratePerKgSnapshotUgx: 5000,
        totalUgx: 19500,
      );

  /// A repo whose update dispatch records the (id, values) and reports
  /// [matched] rows (empty ⇒ no row found ⇒ StateError).
  OrdersRepository repoThat({
    required void Function(String id, Map<String, dynamic> values) record,
    bool matched = true,
  }) =>
      OrdersRepository.forTest(
        clock: () => clock,
        updateRow: (id, values) async {
          record(id, values);
          return matched ? [<String, dynamic>{'id': id}] : const [];
        },
      );

  group('updatePricing', () {
    // A priced order whose stored total_ugx (19500) is deliberately stale vs
    // its inputs, so the test can prove updatePricing dispatches the RECOMPUTED
    // total rather than echoing the stored one.
    LaundryOrder pricedOrder() => order().copyWith(
          finalWeightKg: 4,
          manualAdjustmentUgx: 500,
          deliveryFeeSnapshotUgx: 2000,
        );

    test('dispatches recomputed pricing columns + updated_at for the order id',
        () async {
      late String gotId;
      late Map<String, dynamic> values;
      final repo = repoThat(record: (id, v) {
        gotId = id;
        values = v;
      });

      final o = pricedOrder();
      await repo.updatePricing(o, actorStaffId: 'staff-7');

      expect(gotId, 'o1');
      // Pricing inputs are dispatched verbatim from the order.
      expect(values['estimated_weight_kg'], o.estimatedWeightKg);
      expect(values['final_weight_kg'], 4);
      expect(values['line_items'], const []);
      expect(values['manual_adjustment_ugx'], 500);
      expect(values['delivery_fee_snapshot_ugx'], 2000);
      expect(values['is_express'], false);
      expect(values['express_flat_snapshot_ugx'], 0);
      expect(values['express_pct_snapshot'], 0);
      // total_ugx is the RECOMPUTED total, not the stale stored 19500.
      final recomputed = OrdersRepository.recomputeOrderTotal(o).totalUgx;
      expect(values['total_ugx'], recomputed);
      expect(values['total_ugx'], isNot(19500));
      expect(values['updated_by'], 'staff-7');
      expect(values['updated_at'], '2026-06-24T10:30:00.000Z');
      // Descriptive, status, and creation columns must never leak into a
      // pricing-only update.
      expect(values.containsKey('customer_name'), isFalse);
      expect(values.containsKey('status'), isFalse);
      expect(values.containsKey('created_by'), isFalse);
    });

    test('throws StateError when no row matched', () async {
      final repo = repoThat(record: (_, __) {}, matched: false);
      expect(
        () => repo.updatePricing(pricedOrder(), actorStaffId: 's'),
        throwsStateError,
      );
    });
  });

  group('updateOrderDetails', () {
    test('dispatches the descriptive payload + updated_by for the order id',
        () async {
      late String gotId;
      late Map<String, dynamic> values;
      final repo = repoThat(record: (id, v) {
        gotId = id;
        values = v;
      });

      await repo.updateOrderDetails(order(), actorStaffId: 'staff-7');

      expect(gotId, 'o1');
      expect(values['customer_name'], 'Ada');
      expect(values['phone'], '0700');
      expect(values['service_type'], ServiceType.washAndIron.toDbString());
      expect(values['item_count'], 5);
      expect(values['notes'], 'gate 4');
      expect(values['scheduled_for'], '2026-06-25T09:00:00.000Z');
      expect(values['updated_by'], 'staff-7');
      expect(values['updated_at'], '2026-06-24T10:30:00.000Z');
      // Creation metadata, status, and pricing snapshots must never leak.
      expect(values.containsKey('created_by'), isFalse);
      expect(values.containsKey('status'), isFalse);
      expect(values.containsKey('total_ugx'), isFalse);
    });

    test('throws StateError when no row matched', () async {
      final repo = repoThat(record: (_, __) {}, matched: false);
      expect(
        () => repo.updateOrderDetails(order(), actorStaffId: 's'),
        throwsStateError,
      );
    });
  });

  group('softDelete', () {
    test('dispatches the tombstone payload + deleted_by for the order id',
        () async {
      late String gotId;
      late Map<String, dynamic> values;
      final repo = repoThat(record: (id, v) {
        gotId = id;
        values = v;
      });

      await repo.softDelete('o9', actorStaffId: 'staff-7');

      expect(gotId, 'o9');
      expect(values['deleted_at'], '2026-06-24T10:30:00.000Z');
      expect(values['deleted_by'], 'staff-7');
      expect(values['updated_at'], '2026-06-24T10:30:00.000Z');
    });

    test('throws StateError when no row matched', () async {
      final repo = repoThat(record: (_, __) {}, matched: false);
      expect(
        () => repo.softDelete('missing', actorStaffId: 's'),
        throwsStateError,
      );
    });
  });

  group('updateStatus', () {
    test('dispatches the folded status + updated_by for the order id', () async {
      late String gotId;
      late Map<String, dynamic> values;
      final repo = repoThat(record: (id, v) {
        gotId = id;
        values = v;
      });

      await repo.updateStatus('o1', OrderStatus.readyForDelivery,
          actorStaffId: 'staff-7');

      expect(gotId, 'o1');
      expect(values['status'], OrderStatus.readyForDelivery.toDbString());
      expect(values['updated_by'], 'staff-7');
      expect(values['updated_at'], '2026-06-24T10:30:00.000Z');
    });

    test('throws StateError when no row matched', () async {
      final repo = repoThat(record: (_, __) {}, matched: false);
      expect(
        () => repo.updateStatus('x', OrderStatus.completed, actorStaffId: 's'),
        throwsStateError,
      );
    });
  });
}
