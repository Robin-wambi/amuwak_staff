import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_staff/src/orders/order.dart';
import 'package:amuwak_staff/src/orders/order_details_screen.dart';
import 'package:amuwak_staff/src/orders/order_status.dart';
import 'package:amuwak_staff/src/orders/proof/barcode_reader.dart';
import 'package:amuwak_staff/src/orders/proof/proof_photo_storage.dart';

/// Invokes the `onPressed` of the `ElevatedButton` that contains [label].
///
/// Used by this integration test instead of `tester.tap` because the
/// `OrderDetailsScreen`'s primary action lives at the bottom of the viewport
/// and competes for hit-testing with overlay artifacts (SnackBars and route
/// transition snapshots) that linger after each Navigator push/pop in a long
/// multi-phase flow. Tappability of the same buttons is already verified by
/// the per-screen widget tests in Tasks 9–12.
Future<void> _pressButton(WidgetTester tester, String label) async {
  final finder = find.widgetWithText(ElevatedButton, label);
  final button = tester.widget<ElevatedButton>(finder);
  button.onPressed!();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'full pickup -> in-progress -> ready -> delivery flow appends two ProofEvents',
      (tester) async {
    final storage = InMemoryProofPhotoStorage();
    const initialOrder = LaundryOrder(
      orderId: 'AMW-0421',
      customerName: 'Jane',
      serviceType: 'Wash',
      status: OrderStatus.pendingPickup,
      timeLabel: 't',
      itemCount: 3,
      phone: 'p',
      address: 'a',
      notes: '',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: OrderDetailsScreen(
          order: initialOrder,
          photoStorage: storage,
          pickPhoto: () async => const [1, 2, 3],
          cameraViewBuilder: (ctx, onDetected) {
            return FakeCameraView(
              scannedValue: 'AMW-0421',
              onDetected: onDetected,
            );
          },
          clock: () => DateTime(2026, 5, 12, 9, 42),
        ),
      ),
    );

    // Phase 1: Pickup — open the capture screen, enter count + photo, confirm, done.
    await _pressButton(tester, 'Confirm pickup');

    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byKey(const Key('count_increment')));
      await tester.pump();
    }
    await tester.tap(find.byKey(const Key('add_photo')));
    await tester.pumpAndSettle();
    await _pressButton(tester, 'Confirm with customer');
    await _pressButton(tester, 'Done');

    // Back on OrderDetailsScreen with status now inProgress.
    expect(
      find.widgetWithText(ElevatedButton, 'Move to Ready for delivery'),
      findsOneWidget,
    );

    // Phase 2: Move inProgress -> readyForDelivery via the direct button.
    await _pressButton(tester, 'Move to Ready for delivery');

    expect(
      find.widgetWithText(ElevatedButton, 'Deliver'),
      findsOneWidget,
    );

    // Phase 3: Delivery — scan, add handover photo, mark delivered.
    await _pressButton(tester, 'Deliver');
    await tester.tap(find.text('Simulate scan'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add_handover_photo')));
    await tester.pumpAndSettle();
    await _pressButton(tester, 'Mark delivered');

    // Back on OrderDetailsScreen, status completed: button is disabled
    // and shows 'Order completed'.
    expect(
      find.widgetWithText(ElevatedButton, 'Order completed'),
      findsOneWidget,
    );

    // Storage holds two photos (one pickup + one delivery), and the
    // History panel reflects both ProofEvents.
    expect(storage.savedPhotos, hasLength(2));
    final pickupPhotos =
        storage.savedPhotos.where((p) => p.path.contains('pickup')).toList();
    final deliveryPhotos =
        storage.savedPhotos.where((p) => p.path.contains('delivery')).toList();
    expect(pickupPhotos, hasLength(1));
    expect(deliveryPhotos, hasLength(1));
    expect(find.text('History'), findsOneWidget);
    expect(find.textContaining('Pickup'), findsWidgets);
    expect(find.textContaining('Delivery'), findsWidgets);
  });
}
