import 'package:amuwak_staff/src/data/app_database.dart' show Customer;
import 'package:amuwak_staff/src/orders/order.dart';
import 'package:amuwak_core/amuwak_core.dart';
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

  group('forTest misuse', () {
    test('a write without updateRow trips a descriptive assert, not a bare '
        'null-check crash', () async {
      // forTest with no updateRow leaves both the override and _supabase null;
      // the guard in _updateById must name the omission rather than crashing
      // opaquely on _supabase!.
      final repo = OrdersRepository.forTest(clock: () => clock);
      expect(
        () => repo.softDelete('o1', actorStaffId: 's'),
        throwsA(isA<AssertionError>().having(
            (e) => e.message, 'message', contains('updateRow'))),
      );
    });
  });

  group('upsertOrder', () {
    /// A repo whose upsert dispatch records the column map and reports whether
    /// the write persisted (empty rows ⇒ nothing written ⇒ StateError).
    OrdersRepository repoThatUpserts({
      required void Function(Map<String, dynamic> values) record,
      bool persisted = true,
    }) =>
        OrdersRepository.forTest(
          clock: () => clock,
          upsertRow: (values) async {
            record(values);
            return persisted
                ? [<String, dynamic>{'id': values['id']}]
                : const [];
          },
        );

    test('dispatches the recomputed upsert payload + creation audit pointers',
        () async {
      late Map<String, dynamic> values;
      final repo = repoThatUpserts(record: (v) => values = v);

      final o = order();
      await repo.upsertOrder(o, actorStaffId: 'staff-7');

      expect(values['id'], 'o1');
      expect(values['order_code'], 'AMW-1');
      expect(values['customer_name'], 'Ada');
      expect(values['created_by'], 'staff-7');
      expect(values['intake_recorded_by'], 'staff-7');
      expect(values['created_at'], '2026-06-24T10:30:00.000Z');
      expect(values['updated_at'], '2026-06-24T10:30:00.000Z');
      // total_ugx is the recomputed total, not the stored snapshot.
      expect(values['total_ugx'],
          OrdersRepository.recomputeOrderTotal(o).totalUgx);
    });

    test('throws StateError when the write did not persist', () async {
      final repo = repoThatUpserts(record: (_) {}, persisted: false);
      expect(
        () => repo.upsertOrder(order(), actorStaffId: 's'),
        throwsStateError,
      );
    });

    test('a forTest instance without upsertRow trips a descriptive assert',
        () async {
      final repo = OrdersRepository.forTest(clock: () => clock);
      expect(
        () => repo.upsertOrder(order(), actorStaffId: 's'),
        throwsA(isA<AssertionError>()
            .having((e) => e.message, 'message', contains('upsertRow'))),
      );
    });
  });

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
      expect(values['address'], 'Kira');
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

  group('createPickup', () {
    Customer customer({String id = 'c1'}) => Customer(
          id: id,
          name: 'Ada',
          phone: '0700',
          address: 'Kira',
          notes: null,
          createdAt: clock,
          updatedAt: clock,
          deletedAt: null,
          customRatePerKgUgx: null,
        );

    test('calls the create_pickup RPC with p_customer + p_order and returns '
        'the server order id + minted code', () async {
      String? seenFn;
      Map<String, dynamic>? seenParams;
      final repo = OrdersRepository.forTest(
        clock: () => clock,
        rpc: (fn, params) async {
          seenFn = fn;
          seenParams = params;
          return {'order_id': 'o1', 'order_code': 'AMW-2026-0007'};
        },
      );

      final result = await repo.createPickup(
        order(id: 'o1'),
        customer(id: 'c1'),
        actorStaffId: 's1',
      );

      expect(seenFn, 'create_pickup');
      expect(seenParams!['p_customer'], isA<Map<String, dynamic>>());
      expect((seenParams!['p_customer'] as Map)['id'], 'c1');
      expect((seenParams!['p_order'] as Map)['id'], 'o1');
      // The RPC owns the code/attribution; the client passes the descriptive +
      // pricing fields.
      expect((seenParams!['p_order'] as Map)['service_type'], 'Wash & Iron');
      expect(result.orderId, 'o1');
      expect(result.orderCode, 'AMW-2026-0007');
    });

    test('throws when the RPC returns a result without order_id/order_code',
        () async {
      final repo = OrdersRepository.forTest(
        clock: () => clock,
        rpc: (_, __) async => {'order_id': 'o1'}, // missing order_code
      );
      expect(
        () => repo.createPickup(order(), customer(), actorStaffId: 's'),
        throwsStateError,
      );
    });

    test('a createPickup without an rpc override trips a descriptive assert',
        () async {
      final repo = OrdersRepository.forTest(clock: () => clock);
      expect(
        () => repo.createPickup(order(), customer(), actorStaffId: 's'),
        throwsA(isA<AssertionError>()
            .having((e) => e.message, 'message', contains('rpc'))),
      );
    });
  });
}
