import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_staff/src/orders/order.dart';
import 'package:amuwak_staff/src/orders/order_status.dart';
import 'package:amuwak_staff/src/orders/proof/pickup_capture_screen.dart';
import 'package:amuwak_staff/src/orders/proof/proof_photo_storage.dart';
import 'package:amuwak_staff/src/orders/proof_event.dart';

const _baseOrder = LaundryOrder(
  orderId: 'AMW-0421',
  customerName: 'Jane Doe',
  serviceType: 'Wash & iron',
  status: OrderStatus.pendingPickup,
  timeLabel: 'Today, 09:00',
  itemCount: 12,
  phone: '+234000',
  address: '5 Yaba',
  notes: 'Gate locked',
);

Future<void> _pumpAndPushPickup(
  WidgetTester tester, {
  required InMemoryProofPhotoStorage storage,
  required LaundryOrder order,
  Future<List<int>?> Function()? pickPhoto,
  DateTime Function()? clock,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          return Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  await Navigator.of(context).push<LaundryOrder>(
                    MaterialPageRoute(
                      builder: (_) => PickupCaptureScreen(
                        order: order,
                        photoStorage: storage,
                        pickPhoto:
                            pickPhoto ?? () async => const [1, 2, 3, 4],
                        clock: clock ?? () => DateTime(2026, 5, 12, 9, 42),
                      ),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          );
        },
      ),
    ),
  );

  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'Confirm button is disabled until count > 0 AND at least one photo is captured',
      (tester) async {
    final storage = InMemoryProofPhotoStorage();
    await _pumpAndPushPickup(tester, storage: storage, order: _baseOrder);

    final confirmButton = find.widgetWithText(
      ElevatedButton,
      'Confirm with customer',
    );
    expect(tester.widget<ElevatedButton>(confirmButton).onPressed, isNull);

    // Increment count to 1; still no photo, still disabled.
    await tester.tap(find.byKey(const Key('count_increment')));
    await tester.pump();
    expect(tester.widget<ElevatedButton>(confirmButton).onPressed, isNull);

    // Add a photo; now enabled.
    await tester.tap(find.byKey(const Key('add_photo')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<ElevatedButton>(confirmButton).onPressed,
      isNotNull,
    );
  });

  testWidgets(
      'Tapping Done writes a pickup ProofEvent and pops with status inProgress',
      (tester) async {
    final storage = InMemoryProofPhotoStorage();
    LaundryOrder? captured;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    captured =
                        await Navigator.of(context).push<LaundryOrder>(
                      MaterialPageRoute(
                        builder: (_) => PickupCaptureScreen(
                          order: _baseOrder,
                          photoStorage: storage,
                          pickPhoto: () async => const [10, 20, 30],
                          clock: () => DateTime(2026, 5, 12, 9, 42),
                        ),
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // Bump count to 12.
    for (var i = 0; i < 12; i++) {
      await tester.tap(find.byKey(const Key('count_increment')));
      await tester.pump();
    }

    // Add a photo.
    await tester.tap(find.byKey(const Key('add_photo')));
    await tester.pumpAndSettle();

    // Tap Confirm → moves to QR stage.
    await tester.tap(
      find.widgetWithText(ElevatedButton, 'Confirm with customer'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Tie tag to the bag'), findsOneWidget);

    // Tap Done → pops back with updated order.
    await tester.tap(find.widgetWithText(ElevatedButton, 'Done'));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured!.status, equals(OrderStatus.inProgress));
    expect(captured!.proofEvents, hasLength(1));
    final event = captured!.proofEvents.single;
    expect(event.type, equals(ProofEventType.pickup));
    expect(event.count, equals(12));
    expect(event.photoPaths, hasLength(1));
    expect(storage.savedPhotos, hasLength(1));
    expect(storage.savedPhotos.single.bytes, equals(const [10, 20, 30]));
  });
}
