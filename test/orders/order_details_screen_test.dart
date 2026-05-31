import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Hide Drift's `ProofEvent` (the row class) so the existing tests that use the
// domain `ProofEvent` from `orders/proof_event.dart` stay unambiguous.
import 'package:amuwak_staff/src/data/app_database.dart' hide ProofEvent;
import 'package:amuwak_staff/src/orders/order.dart';
import 'package:amuwak_staff/src/orders/order_details_screen.dart';
import 'package:amuwak_staff/src/orders/order_status.dart';
import 'package:amuwak_staff/src/orders/service_type.dart';
import 'package:amuwak_staff/src/orders/proof/barcode_reader.dart';
import 'package:amuwak_staff/src/orders/proof/proof_photo_storage.dart';
import 'package:amuwak_staff/src/orders/proof_event.dart';
import 'package:amuwak_staff/src/shared/widgets/app_theme.dart';
import 'package:amuwak_staff/src/sync/orders_repository.dart';
import 'package:amuwak_staff/src/sync/outbox_repository.dart';
import 'package:amuwak_staff/src/sync/proof_events_repository.dart';

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

/// Bundles an in-memory Drift DB + outbox + repos for tests that exercise
/// the write path through OrdersRepository.
class _AdvanceFixture {
  _AdvanceFixture._(this.db, this.outbox, this.ordersRepo, this.proofEventsRepo);

  final AppDatabase db;
  final OutboxRepository outbox;
  final OrdersRepository ordersRepo;
  final ProofEventsRepository proofEventsRepo;

  static _AdvanceFixture create() {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final outbox = OutboxRepository(db);
    final ordersRepo = OrdersRepository(
      db,
      outbox: outbox,
      clock: () => DateTime.utc(2026, 5, 21, 12, 0),
    );
    final proofEventsRepo = ProofEventsRepository(db, outbox: outbox);
    return _AdvanceFixture._(db, outbox, ordersRepo, proofEventsRepo);
  }
}

/// Seeds an `orders` row matching [order] directly into the Drift DB so the
/// repo's `updateStatus` will find it. Uses the same column shape as
/// `test/sync/orders_repository_write_test.dart`.
Future<void> _seedOrder(AppDatabase db, LaundryOrder order) {
  return db.into(db.orders).insert(OrdersCompanion.insert(
        id: order.orderId,
        orderCode: order.orderId,
        customerName: order.customerName,
        phone: order.phone,
        address: order.address,
        serviceType: order.serviceType.toDbString(),
        status: order.status.toDbString(),
        intakeMethod: 'driver_pickup',
        fulfillmentMethod: 'delivery',
        itemCount: order.itemCount,
        intakeRecordedBy: 's-test',
        createdBy: 's-test',
      ));
}

/// Lazily-constructed placeholder DB shared by all _wrap calls that don't
/// supply repos. Constructed once to avoid Drift's "multiple AppDatabase
/// instances" warning. Read-only by construction (no outbox wired), so any
/// accidental write surfaces as a StateError rather than silently succeeding.
AppDatabase? _placeholderDb;
AppDatabase _ensurePlaceholderDb() =>
    _placeholderDb ??= AppDatabase.forTesting(NativeDatabase.memory());

Widget _wrap(
  LaundryOrder order, {
  required InMemoryProofPhotoStorage storage,
  String scannedValue = 'AMW-0421',
  Future<List<int>?> Function()? pickPhoto,
  OrdersRepository? ordersRepo,
  ProofEventsRepository? proofEventsRepo,
  String actorStaffId = 's-test',
}) {
  final effectiveOrdersRepo =
      ordersRepo ?? OrdersRepository(_ensurePlaceholderDb());
  final effectiveProofEventsRepo =
      proofEventsRepo ?? ProofEventsRepository(_ensurePlaceholderDb());
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
      ordersRepo: effectiveOrdersRepo,
      proofEventsRepo: effectiveProofEventsRepo,
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
      'inProgress advances status by writing through OrdersRepository '
      '(DB row + outbox update)', (tester) async {
    final fixture = _AdvanceFixture.create();
    addTearDown(() async => fixture.db.close());

    final storage = InMemoryProofPhotoStorage();
    final inProgress = _pendingPickup.copyWith(status: OrderStatus.inProgress);
    await _seedOrder(fixture.db, inProgress);

    await tester.pumpWidget(_wrap(
      inProgress,
      storage: storage,
      ordersRepo: fixture.ordersRepo,
      proofEventsRepo: fixture.proofEventsRepo,
    ));

    // The button is the one we expect.
    expect(
      find.widgetWithText(ElevatedButton, 'Move to Ready for delivery'),
      findsOneWidget,
    );

    await tester
        .tap(find.widgetWithText(ElevatedButton, 'Move to Ready for delivery'));
    await tester.pumpAndSettle();

    // DB row was updated to 'ready'.
    final row = await (fixture.db.select(fixture.db.orders)
          ..where((t) => t.id.equals('AMW-0421')))
        .getSingle();
    expect(row.status, 'ready');

    // Outbox has the matching update row.
    final outboxRows = await fixture.db.select(fixture.db.outbox).get();
    expect(outboxRows, hasLength(1));
    expect(outboxRows.single.forTable, 'orders');
    expect(outboxRows.single.op, 'update');
    expect(outboxRows.single.rowId, 'AMW-0421');
    final payload = jsonDecode(outboxRows.single.payloadJson) as Map;
    expect(payload['status'], 'ready');
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
      // Wrap fixes today = 2026-05-12 via the injected clock.
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
      // Date prefix must NOT appear for a same-day event.
      expect(find.textContaining('May'), findsNothing);
      expect(find.textContaining('12 May'), findsNothing);
    },
  );

  testWidgets(
    'History row for an event on a different day prepends the date',
    (tester) async {
      final storage = InMemoryProofPhotoStorage();
      // Wrap fixes today = 2026-05-12. Pickup happened yesterday.
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

      // Yesterday's pickup is dated.
      expect(find.textContaining('11 May'), findsOneWidget);
      expect(find.textContaining('22:15'), findsOneWidget);
      // Today's delivery is time-only.
      expect(find.textContaining('08:30'), findsOneWidget);
    },
  );
}
