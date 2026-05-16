import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_staff/src/orders/order.dart';
import 'package:amuwak_staff/src/orders/order_status.dart';
import 'package:amuwak_staff/src/orders/proof/delivery_capture_screen.dart';
import 'package:amuwak_staff/src/orders/proof/proof_photo_storage.dart';
import 'package:amuwak_staff/src/orders/proof_event.dart';

class _ThrowingProofPhotoStorage implements ProofPhotoStorage {
  @override
  Future<String> save({
    required String orderId,
    required ProofEventType type,
    required int index,
    required List<int> bytes,
  }) async {
    throw Exception('disk full');
  }
}

LaundryOrder _orderReadyForDelivery() {
  return LaundryOrder(
    orderId: 'AMW-0421',
    customerName: 'Jane Doe',
    serviceType: 'Wash & iron',
    status: OrderStatus.readyForDelivery,
    timeLabel: 'Today, 16:00',
    itemCount: 12,
    phone: '+234000',
    address: '5 Yaba',
    notes: '',
    proofEvents: [
      ProofEvent(
        type: ProofEventType.pickup,
        capturedAt: DateTime(2026, 5, 12, 9, 42),
        count: 12,
        photoPaths: const ['memory://AMW-0421/pickup_0'],
      ),
    ],
  );
}

void main() {
  testWidgets('Mark delivered is disabled until a handover photo is captured',
      (tester) async {
    final storage = InMemoryProofPhotoStorage();
    final order = _orderReadyForDelivery();

    await tester.pumpWidget(
      MaterialApp(
        home: DeliveryCaptureScreen(
          order: order,
          photoStorage: storage,
          pickPhoto: () async => const [1, 2, 3],
          clock: () => DateTime(2026, 5, 12, 16, 13),
        ),
      ),
    );

    final button = find.widgetWithText(ElevatedButton, 'Mark delivered');
    expect(tester.widget<ElevatedButton>(button).onPressed, isNull);
    expect(find.text('Pickup count: 12'), findsOneWidget);

    await tester.tap(find.byKey(const Key('add_handover_photo')));
    await tester.pumpAndSettle();

    expect(tester.widget<ElevatedButton>(button).onPressed, isNotNull);
  });

  testWidgets(
      'Mark delivered appends a delivery ProofEvent and pops with status completed',
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
                        builder: (_) => DeliveryCaptureScreen(
                          order: _orderReadyForDelivery(),
                          photoStorage: storage,
                          pickPhoto: () async => const [50, 60, 70],
                          clock: () => DateTime(2026, 5, 12, 16, 13),
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

    await tester.tap(find.byKey(const Key('add_handover_photo')));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ElevatedButton, 'Mark delivered'));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured!.status, equals(OrderStatus.completed));
    expect(captured!.proofEvents, hasLength(2));
    final delivery = captured!.deliveryProof!;
    expect(delivery.type, equals(ProofEventType.delivery));
    expect(delivery.photoPaths, hasLength(1));
    expect(storage.savedPhotos, hasLength(1));
    expect(storage.savedPhotos.single.bytes, equals(const [50, 60, 70]));
  });

  testWidgets(
    'Mark delivered re-enables itself and surfaces an error when photo save fails',
    (tester) async {
      LaundryOrder? captured;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      captured = await Navigator.of(context).push<LaundryOrder>(
                        MaterialPageRoute(
                          builder: (_) => DeliveryCaptureScreen(
                            order: _orderReadyForDelivery(),
                            photoStorage: _ThrowingProofPhotoStorage(),
                            pickPhoto: () async => const [50, 60, 70],
                            clock: () => DateTime(2026, 5, 12, 16, 13),
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

      await tester.tap(find.byKey(const Key('add_handover_photo')));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Mark delivered'));
      await tester.pumpAndSettle();

      expect(captured, isNull);
      expect(find.byType(DeliveryCaptureScreen), findsOneWidget);
      final markDelivered = find.widgetWithText(
        ElevatedButton,
        'Mark delivered',
      );
      expect(
        tester.widget<ElevatedButton>(markDelivered).onPressed,
        isNotNull,
      );
      expect(
        find.textContaining('Could not save delivery proof'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Rapid taps on add handover photo only trigger one pickPhoto and hide the tile',
    (tester) async {
      final completers = <Completer<List<int>?>>[];

      await tester.pumpWidget(
        MaterialApp(
          home: DeliveryCaptureScreen(
            order: _orderReadyForDelivery(),
            photoStorage: InMemoryProofPhotoStorage(),
            pickPhoto: () {
              final c = Completer<List<int>?>();
              completers.add(c);
              return c.future;
            },
            clock: () => DateTime(2026, 5, 12, 16, 13),
          ),
        ),
      );

      final addTile = find.byKey(const Key('add_handover_photo'));
      for (var i = 0; i < 5; i++) {
        await tester.tap(addTile);
      }
      await tester.pump();

      expect(completers, hasLength(1));
      expect(find.byKey(const Key('add_handover_photo')), findsNothing);

      completers.first.complete(const [4, 5, 6]);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('add_handover_photo')), findsOneWidget);
      expect(completers, hasLength(1));
    },
  );
}
