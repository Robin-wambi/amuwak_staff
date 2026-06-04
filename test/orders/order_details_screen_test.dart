import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:amuwak_staff/src/orders/order.dart';
import 'package:amuwak_staff/src/orders/order_details_screen.dart';
import 'package:amuwak_staff/src/orders/order_status.dart';
import 'package:amuwak_staff/src/orders/service_type.dart';
import 'package:amuwak_staff/src/orders/proof/proof_photo_storage.dart';
import 'package:amuwak_staff/src/orders/proof_event.dart';
import 'package:amuwak_staff/src/shared/widgets/app_theme.dart';
import 'package:amuwak_staff/src/sync/orders_repository.dart';
import 'package:amuwak_staff/src/sync/proof_events_repository.dart';

import '../helpers/fake_camera_view.dart';

/// Online-only mode: OrderDetailsScreen takes Supabase-backed repos via its
/// constructor. These tests mock them — the screen only *reads* from the
/// in-memory [LaundryOrder] passed in (no stream subscriptions), and the one
/// status-advance path is verified by capturing the [OrdersRepository.updateStatus]
/// call (replacing the old Drift row + outbox inspection).
class _MockOrdersRepository extends Mock implements OrdersRepository {}

class _MockProofEventsRepository extends Mock
    implements ProofEventsRepository {}

const _pendingPickup = LaundryOrder(
  orderId: 'AMW-0421',
  customerName: 'Jane',
  serviceType: ServiceType.washOnly,
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
  OrdersRepository? ordersRepo,
  ProofEventsRepository? proofEventsRepo,
  String actorStaffId = 's-test',
}) {
  return MaterialApp(
    theme: buildAmuwakTheme(),
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
      ordersRepo: ordersRepo ?? _MockOrdersRepository(),
      proofEventsRepo: proofEventsRepo ?? _MockProofEventsRepository(),
      actorStaffId: actorStaffId,
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
          id: 'pe-test-1',
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

  testWidgets(
      'order details shows the human order code, never the UUID order id',
      (tester) async {
    final storage = InMemoryProofPhotoStorage();
    // Distinct orderId (UUID) and orderCode so the screen can't pass by the two
    // being accidentally equal (as in the shared _pendingPickup fixture).
    final coded = _pendingPickup.copyWith(
      orderId: '019e9147-608b-72b7-9e2c-0baa04e85094',
      orderCode: 'AMW-2026-0042',
    );

    await tester.pumpWidget(_wrap(coded, storage: storage));

    // The short code is shown (header + the "Order code" detail row)...
    expect(find.textContaining('AMW-2026-0042'), findsWidgets);
    // ...and the long UUID is never put in front of the rider.
    expect(
      find.textContaining('019e9147-608b-72b7-9e2c-0baa04e85094'),
      findsNothing,
    );
  });

  testWidgets(
      'Deliver verification matches the human order code, not the UUID order id',
      (tester) async {
    final storage = InMemoryProofPhotoStorage();
    // orderId is the internal UUID; the bag tag the rider scans carries the
    // short order CODE. These MUST differ so the scan can only succeed if the
    // screen verifies against orderCode (not orderId).
    final coded = _pendingPickup.copyWith(
      orderId: '019e9147-608b-72b7-9e2c-0baa04e85094',
      orderCode: 'AMW-2026-0042',
      status: OrderStatus.readyForDelivery,
      proofEvents: [
        ProofEvent(
          id: 'pe-test-1',
          type: ProofEventType.pickup,
          capturedAt: DateTime(2026, 5, 12, 9, 42),
          count: 12,
          photoPaths: const ['memory://AMW-2026-0042/pickup_0'],
        ),
      ],
    );

    await tester.pumpWidget(_wrap(
      coded,
      storage: storage,
      scannedValue: 'AMW-2026-0042',
    ));

    await tester.tap(find.widgetWithText(ElevatedButton, 'Deliver'));
    await tester.pumpAndSettle();
    expect(find.text('Scan order tag'), findsOneWidget);

    await tester.tap(find.text('Simulate scan'));
    await tester.pumpAndSettle();

    // Scanning the order code satisfied verification and advanced to delivery.
    expect(find.text('Hand over'), findsOneWidget);
  });

  testWidgets(
      'inProgress advances status by writing through OrdersRepository.updateStatus',
      (tester) async {
    final ordersRepo = _MockOrdersRepository();
    when(() => ordersRepo.updateStatus(
          'AMW-0421',
          OrderStatus.readyForDelivery,
          actorStaffId: any(named: 'actorStaffId'),
        )).thenAnswer((_) async {});

    final storage = InMemoryProofPhotoStorage();
    final inProgress = _pendingPickup.copyWith(status: OrderStatus.inProgress);

    await tester.pumpWidget(_wrap(
      inProgress,
      storage: storage,
      ordersRepo: ordersRepo,
    ));

    expect(
      find.widgetWithText(ElevatedButton, 'Move to Ready for delivery'),
      findsOneWidget,
    );

    await tester
        .tap(find.widgetWithText(ElevatedButton, 'Move to Ready for delivery'));
    await tester.pumpAndSettle();

    // The screen advanced inProgress → readyForDelivery through the repo.
    verify(() => ordersRepo.updateStatus(
          'AMW-0421',
          OrderStatus.readyForDelivery,
          actorStaffId: 's-test',
        )).called(1);
  });

  testWidgets('order with proofEvents renders a History panel', (tester) async {
    final storage = InMemoryProofPhotoStorage();
    final delivered = _pendingPickup.copyWith(
      status: OrderStatus.completed,
      proofEvents: [
        ProofEvent(
          id: 'pe-test-1',
          type: ProofEventType.pickup,
          capturedAt: DateTime(2026, 5, 12, 9, 42),
          count: 12,
          photoPaths: const ['memory://AMW-0421/pickup_0'],
        ),
        ProofEvent(
          id: 'pe-test-2',
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

  testWidgets(
    'History row for same-day event shows only HH:mm — no date',
    (tester) async {
      final storage = InMemoryProofPhotoStorage();
      final sameDay = _pendingPickup.copyWith(
        status: OrderStatus.completed,
        proofEvents: [
          ProofEvent(
            id: 'pe-test-1',
            type: ProofEventType.pickup,
            capturedAt: DateTime(2026, 5, 12, 9, 42),
            count: 12,
            photoPaths: const ['memory://AMW-0421/pickup_0'],
          ),
        ],
      );

      await tester.pumpWidget(_wrap(sameDay, storage: storage));

      expect(find.textContaining('09:42'), findsOneWidget);
      expect(find.textContaining('May'), findsNothing);
      expect(find.textContaining('12 May'), findsNothing);
    },
  );

  testWidgets(
    'History row for an event on a different day prepends the date',
    (tester) async {
      final storage = InMemoryProofPhotoStorage();
      final spansMidnight = _pendingPickup.copyWith(
        status: OrderStatus.completed,
        proofEvents: [
          ProofEvent(
            id: 'pe-test-1',
            type: ProofEventType.pickup,
            capturedAt: DateTime(2026, 5, 11, 22, 15),
            count: 12,
            photoPaths: const ['memory://AMW-0421/pickup_0'],
          ),
          ProofEvent(
            id: 'pe-test-2',
            type: ProofEventType.delivery,
            capturedAt: DateTime(2026, 5, 12, 8, 30),
            count: 12,
            photoPaths: const ['memory://AMW-0421/delivery_0'],
          ),
        ],
      );

      await tester.pumpWidget(_wrap(spansMidnight, storage: storage));

      expect(find.textContaining('11 May'), findsOneWidget);
      expect(find.textContaining('22:15'), findsOneWidget);
      expect(find.textContaining('08:30'), findsOneWidget);
    },
  );
}
