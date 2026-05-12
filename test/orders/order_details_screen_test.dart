import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_staff/src/orders/order.dart';
import 'package:amuwak_staff/src/orders/order_details_screen.dart';
import 'package:amuwak_staff/src/orders/order_status.dart';
import 'package:amuwak_staff/src/orders/proof/barcode_reader.dart';
import 'package:amuwak_staff/src/orders/proof/proof_photo_storage.dart';
import 'package:amuwak_staff/src/orders/proof_event.dart';

const _pendingPickup = LaundryOrder(
  orderId: 'AMW-0421',
  customerName: 'Jane',
  serviceType: 'Wash',
  status: OrderStatus.pendingPickup,
  timeLabel: 't',
  itemCount: 12,
  phone: 'p',
  address: 'a',
  notes: '',
);

Widget _wrap(
  LaundryOrder order, {
  required InMemoryProofPhotoStorage storage,
  String scannedValue = 'AMW-0421',
  Future<List<int>?> Function()? pickPhoto,
}) {
  return MaterialApp(
    home: OrderDetailsScreen(
      order: order,
      photoStorage: storage,
      pickPhoto: pickPhoto ?? () async => const [1, 2, 3],
      cameraViewBuilder: (context, onDetected) {
        return FakeCameraView(
          scannedValue: scannedValue,
          onDetected: onDetected,
        );
      },
      clock: () => DateTime(2026, 5, 12, 9, 42),
    ),
  );
}

void main() {
  testWidgets(
      'pendingPickup shows "Confirm pickup" and routes to PickupCaptureScreen',
      (tester) async {
    final storage = InMemoryProofPhotoStorage();
    await tester.pumpWidget(_wrap(_pendingPickup, storage: storage));

    expect(
      find.widgetWithText(ElevatedButton, 'Confirm pickup'),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(ElevatedButton, 'Confirm pickup'));
    await tester.pumpAndSettle();

    expect(find.text('How many items?'), findsOneWidget);
  });

  testWidgets(
      'readyForDelivery shows "Deliver" and routes through scanner to delivery',
      (tester) async {
    final storage = InMemoryProofPhotoStorage();
    final readyOrder = _pendingPickup.copyWith(
      status: OrderStatus.readyForDelivery,
      proofEvents: [
        ProofEvent(
          type: ProofEventType.pickup,
          capturedAt: DateTime(2026, 5, 12, 9, 42),
          count: 12,
          photoPaths: const ['memory://AMW-0421/pickup_0'],
        ),
      ],
    );

    await tester.pumpWidget(_wrap(readyOrder, storage: storage));

    await tester.tap(find.widgetWithText(ElevatedButton, 'Deliver'));
    await tester.pumpAndSettle();

    expect(find.text('Scan order tag'), findsOneWidget);

    await tester.tap(find.text('Simulate scan'));
    await tester.pumpAndSettle();

    expect(find.text('Hand over'), findsOneWidget);
  });

  testWidgets('inProgress keeps existing direct status-advance button',
      (tester) async {
    final storage = InMemoryProofPhotoStorage();
    final inProgress = _pendingPickup.copyWith(status: OrderStatus.inProgress);

    await tester.pumpWidget(_wrap(inProgress, storage: storage));

    expect(
      find.widgetWithText(ElevatedButton, 'Move to Ready for delivery'),
      findsOneWidget,
    );
  });

  testWidgets('order with proofEvents renders a History panel', (tester) async {
    final storage = InMemoryProofPhotoStorage();
    final delivered = _pendingPickup.copyWith(
      status: OrderStatus.completed,
      proofEvents: [
        ProofEvent(
          type: ProofEventType.pickup,
          capturedAt: DateTime(2026, 5, 12, 9, 42),
          count: 12,
          photoPaths: const ['memory://AMW-0421/pickup_0'],
        ),
        ProofEvent(
          type: ProofEventType.delivery,
          capturedAt: DateTime(2026, 5, 12, 16, 13),
          count: 12,
          photoPaths: const ['memory://AMW-0421/delivery_0'],
        ),
      ],
    );

    await tester.pumpWidget(_wrap(delivered, storage: storage));

    expect(find.text('History'), findsOneWidget);
    expect(find.textContaining('Pickup'), findsWidgets);
    expect(find.textContaining('Delivery'), findsWidgets);
  });
}
