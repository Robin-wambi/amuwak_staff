import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:amuwak_staff/src/orders/order.dart';
import 'package:amuwak_staff/src/orders/order_details_screen.dart';
import 'package:amuwak_staff/src/orders/order_status.dart';
import 'package:amuwak_staff/src/orders/service_type.dart';
import 'package:amuwak_staff/src/orders/proof/proof_photo_storage.dart';
import 'package:amuwak_staff/src/pricing/catalog_item.dart';
import 'package:amuwak_staff/src/shared/widgets/app_theme.dart';
import 'package:amuwak_staff/src/sync/orders_repository.dart';
import 'package:amuwak_staff/src/sync/proof_events_repository.dart';

import '../helpers/fake_camera_view.dart';

class _MockOrdersRepository extends Mock implements OrdersRepository {}

class _MockProofEventsRepository extends Mock
    implements ProofEventsRepository {}

const _baseOrder = LaundryOrder(
  orderId: 'AMW-0001',
  customerName: 'Alice',
  serviceType: ServiceType.washOnly,
  status: OrderStatus.inProgress,
  timeLabel: 't',
  itemCount: 5,
  phone: 'p',
  address: 'a',
  notes: '',
  ratePerKgSnapshotUgx: 5000,
);

Widget _wrap(
  LaundryOrder order, {
  OrdersRepository? ordersRepo,
  String actorStaffId = 's-test',
  List<CatalogItem> catalogItems = const [],
}) {
  return MaterialApp(
    theme: buildAmuwakTheme(),
    home: OrderDetailsScreen(
      order: order,
      photoStorage: InMemoryProofPhotoStorage(),
      pickPhoto: () async => const [1, 2, 3],
      cameraViewBuilder: (context, onDetected) => FakeCameraView(
        scannedValue: 'AMW-0001',
        onDetected: onDetected,
      ),
      clock: () => DateTime(2026, 5, 12, 9, 42),
      ordersRepo: ordersRepo ?? _MockOrdersRepository(),
      proofEventsRepo: _MockProofEventsRepository(),
      actorStaffId: actorStaffId,
      catalogItems: catalogItems,
    ),
  );
}

void main() {
  setUpAll(() => registerFallbackValue(OrderStatus.pendingPickup));

  testWidgets(
    'inProgress: rate row shows USh 5,000/kg; entering final weight shows total and removes Provisional badge',
    (tester) async {
      await tester.pumpWidget(_wrap(_baseOrder));

      // Rate row is visible.
      expect(find.text('USh 5,000/kg'), findsOneWidget);

      // Initially no final weight → total is provisional.
      expect(find.text('Provisional'), findsOneWidget);

      // Enter final weight of 4 kg → total should be USh 20,000, no Provisional.
      await tester.enterText(find.byKey(const Key('details_final_weight')), '4');
      await tester.pump();

      expect(find.text('USh 20,000'), findsOneWidget);
      expect(find.text('Provisional'), findsNothing);
    },
  );

  testWidgets(
    'pendingPickup: Pricing section is absent',
    (tester) async {
      final pendingOrder = _baseOrder.copyWith(
        status: OrderStatus.pendingPickup,
      );

      await tester.pumpWidget(_wrap(pendingOrder));

      expect(find.byKey(const Key('details_final_weight')), findsNothing);
      expect(find.byKey(const Key('details_save_pricing')), findsNothing);
    },
  );

  testWidgets(
    'total includes the frozen delivery fee and express surcharge',
    (tester) async {
      final order = _baseOrder.copyWith(
        deliveryFeeSnapshotUgx: 3000,
        isExpress: true,
        expressFlatSnapshotUgx: 1000,
        expressPctSnapshot: 20, // 20% of weight charge
      );
      await tester.pumpWidget(_wrap(order));

      await tester.enterText(find.byKey(const Key('details_final_weight')), '2');
      await tester.pump();
      // weight 10000 + express (1000 + 20% of 10000 = 3000) + delivery 3000.
      expect(find.text('USh 3,000'), findsWidgets); // express + delivery rows
      expect(find.text('USh 16,000'), findsOneWidget); // total
      expect(find.text('Express'), findsOneWidget);
      expect(find.text('Delivery'), findsOneWidget);
    },
  );

  testWidgets(
    'adds a catalog item through the picker',
    (tester) async {
      await tester.pumpWidget(_wrap(
        _baseOrder,
        catalogItems: [
          CatalogItem(id: 'c1', name: 'Blanket', amountUgx: 8000),
        ],
      ));
      await tester.enterText(find.byKey(const Key('details_final_weight')), '1');
      await tester.pump();

      await tester.ensureVisible(find.byKey(const Key('add_line_item')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('add_line_item')));
      await tester.pumpAndSettle();
      // The catalog item appears in the picker; tapping it adds a line.
      await tester.tap(find.byKey(const Key('pick_catalog_item_0')));
      await tester.pumpAndSettle();

      // 5000 weight + 8000 blanket = 13000.
      expect(find.text('USh 13,000'), findsOneWidget);
    },
  );
}
