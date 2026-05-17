import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_staff/src/orders/order.dart';
import 'package:amuwak_staff/src/orders/order_status.dart';
import 'package:amuwak_staff/src/orders/proof/pickup_capture_screen.dart';
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

  testWidgets(
    'Done re-enables itself and surfaces an error when photo save fails',
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
                          builder: (_) => PickupCaptureScreen(
                            order: _baseOrder,
                            photoStorage: _ThrowingProofPhotoStorage(),
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

      await tester.tap(find.byKey(const Key('count_increment')));
      await tester.tap(find.byKey(const Key('add_photo')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(ElevatedButton, 'Confirm with customer'),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Done'));
      await tester.pumpAndSettle();

      // Push has not resolved — the screen did not pop.
      expect(captured, isNull);
      expect(find.text('Tie tag to the bag'), findsOneWidget);
      // Done button is re-enabled so the user can retry.
      final done = find.widgetWithText(ElevatedButton, 'Done');
      expect(tester.widget<ElevatedButton>(done).onPressed, isNotNull);
      // User-facing error feedback is visible.
      expect(
        find.textContaining('Could not save pickup proof'),
        findsOneWidget,
      );
      // The exception was handled, not left dangling.
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Rapid taps on add photo only trigger one pickPhoto and hide the tile',
    (tester) async {
      final completers = <Completer<List<int>?>>[];

      await tester.pumpWidget(
        MaterialApp(
          home: PickupCaptureScreen(
            order: _baseOrder,
            photoStorage: InMemoryProofPhotoStorage(),
            pickPhoto: () {
              final c = Completer<List<int>?>();
              completers.add(c);
              return c.future;
            },
            clock: () => DateTime(2026, 5, 12, 9, 42),
          ),
        ),
      );

      final addTile = find.byKey(const Key('add_photo'));
      // Five rapid taps before any rebuild — only one pickPhoto must fly.
      for (var i = 0; i < 5; i++) {
        await tester.tap(addTile);
      }
      await tester.pump();

      expect(completers, hasLength(1));
      // While picking, the tile is hidden so the user can't queue more taps.
      expect(find.byKey(const Key('add_photo')), findsNothing);

      // Resolve the pick. The tile should reappear (still under _maxPhotos).
      completers.first.complete(const [1, 2, 3]);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('add_photo')), findsOneWidget);
      expect(completers, hasLength(1));
    },
  );

  testWidgets(
    'Captured photo thumbnail renders the bytes via MemoryImage',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PickupCaptureScreen(
            order: _baseOrder,
            photoStorage: InMemoryProofPhotoStorage(),
            pickPhoto: () async => const [9, 8, 7, 6, 5],
            clock: () => DateTime(2026, 5, 12, 9, 42),
          ),
        ),
      );

      // No photo yet → no Image widget in the slot row.
      expect(find.byType(Image), findsNothing);

      await tester.tap(find.byKey(const Key('add_photo')));
      await tester.pumpAndSettle();

      final images = tester.widgetList<Image>(find.byType(Image)).toList();
      expect(images, hasLength(1));
      final image = images.single;
      expect(image.image, isA<MemoryImage>());
      final memoryImage = image.image as MemoryImage;
      expect(memoryImage.bytes, equals(Uint8List.fromList(const [9, 8, 7, 6, 5])));
    },
  );

  testWidgets(
    'Add photo recovers and surfaces an error when pickPhoto throws',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PickupCaptureScreen(
            order: _baseOrder,
            photoStorage: InMemoryProofPhotoStorage(),
            pickPhoto: () async {
              throw Exception('camera permission revoked');
            },
            clock: () => DateTime(2026, 5, 12, 9, 42),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('add_photo')));
      await tester.pumpAndSettle();

      // No photo was added — the tile is still available for retry.
      expect(find.byKey(const Key('add_photo')), findsOneWidget);
      // User-facing error feedback is visible.
      expect(
        find.textContaining('Could not open camera'),
        findsOneWidget,
      );
      // The exception was handled, not left dangling.
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Back from QR stage returns to collecting without losing count/photos/notes',
    (tester) async {
      final storage = InMemoryProofPhotoStorage();
      LaundryOrder? captured;
      var poppedFromPush = false;

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
                          builder: (_) => PickupCaptureScreen(
                            order: _baseOrder,
                            photoStorage: storage,
                            pickPhoto: () async => const [10, 20, 30],
                            clock: () => DateTime(2026, 5, 12, 9, 42),
                          ),
                        ),
                      );
                      poppedFromPush = true;
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

      // Enter count, photo, notes.
      for (var i = 0; i < 7; i++) {
        await tester.tap(find.byKey(const Key('count_increment')));
        await tester.pump();
      }
      await tester.tap(find.byKey(const Key('add_photo')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField),
        'fragile silk',
      );
      await tester.pump();

      // Move to QR stage.
      await tester.tap(
        find.widgetWithText(ElevatedButton, 'Confirm with customer'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Tie tag to the bag'), findsOneWidget);

      // Tap the AppBar back arrow.
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      // We should be back on the collecting stage, NOT have left the route.
      expect(poppedFromPush, isFalse);
      expect(captured, isNull);
      expect(find.text('Tie tag to the bag'), findsNothing);
      expect(find.text('Confirm with customer'), findsOneWidget);

      // Count, photo, and notes are preserved.
      expect(find.text('7'), findsOneWidget);
      expect(find.text('Photos (1/3)'), findsOneWidget);
      expect(find.text('fragile silk'), findsOneWidget);
    },
  );
}
