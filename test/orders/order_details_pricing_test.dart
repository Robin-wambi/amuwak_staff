import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:amuwak_staff/src/orders/order.dart';
import 'package:amuwak_staff/src/orders/order_details_screen.dart';
import 'package:amuwak_staff/src/orders/order_status.dart';
import 'package:amuwak_staff/src/orders/service_type.dart';
import 'package:amuwak_staff/src/orders/proof/proof_photo_storage.dart';
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
}
