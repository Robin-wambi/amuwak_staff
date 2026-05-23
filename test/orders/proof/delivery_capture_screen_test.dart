import 'dart:async';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Hide Drift's row class `ProofEvent` so the tests can keep referring to the
// domain `ProofEvent` from `orders/proof_event.dart` without ambiguity.
import 'package:amuwak_staff/src/data/app_database.dart' hide ProofEvent;
import 'package:amuwak_staff/src/orders/order.dart';
import 'package:amuwak_staff/src/orders/order_status.dart';
import 'package:amuwak_staff/src/orders/proof/delivery_capture_screen.dart';
import 'package:amuwak_staff/src/orders/proof/proof_photo_storage.dart';
import 'package:amuwak_staff/src/orders/proof_event.dart';
import 'package:amuwak_staff/src/sync/orders_repository.dart';
import 'package:amuwak_staff/src/sync/outbox_repository.dart';
import 'package:amuwak_staff/src/sync/proof_events_repository.dart';

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

/// Wraps a real [OrdersRepository] but rigs `updateStatus` to throw on the
/// first call and delegate on subsequent calls. Used to exercise the
/// capture-screen retry path: insert proof succeeds, status update fails,
/// user retries, status update succeeds.
class _FlakyUpdateOrdersRepo extends OrdersRepository {
  _FlakyUpdateOrdersRepo(super.db, {required super.outbox});

  int _calls = 0;

  @override
  Future<void> updateStatus(String orderId, OrderStatus newStatus,
      {required String actorStaffId}) async {
    _calls += 1;
    if (_calls == 1) {
      throw Exception('transient flake');
    }
    return super.updateStatus(orderId, newStatus, actorStaffId: actorStaffId);
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
        id: 'pe-test-1',
        type: ProofEventType.pickup,
        capturedAt: DateTime(2026, 5, 12, 9, 42),
        count: 12,
        photoPaths: const ['memory://AMW-0421/pickup_0'],
      ),
    ],
  );
}

/// Bundles an in-memory Drift DB + outbox + wired repos for tests that need
/// to assert the write path lands the right rows.
class _DeliveryFixture {
  _DeliveryFixture._(this.db, this.outbox, this.ordersRepo, this.proofEventsRepo);

  final AppDatabase db;
  final OutboxRepository outbox;
  final OrdersRepository ordersRepo;
  final ProofEventsRepository proofEventsRepo;

  static _DeliveryFixture create() {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final outbox = OutboxRepository(db);
    final ordersRepo = OrdersRepository(
      db,
      outbox: outbox,
      clock: () => DateTime.utc(2026, 5, 21, 12, 0),
      uuid: () => 'orders-mut',
    );
    final proofEventsRepo = ProofEventsRepository(
      db,
      outbox: outbox,
      clock: () => DateTime.utc(2026, 5, 21, 12, 0),
      uuid: () => 'pe-mut',
    );
    return _DeliveryFixture._(db, outbox, ordersRepo, proofEventsRepo);
  }
}

/// Seeds an `orders` row matching [order] directly into the Drift DB.
Future<void> _seedOrder(AppDatabase db, LaundryOrder order) {
  return db.into(db.orders).insert(OrdersCompanion.insert(
        id: order.orderId,
        orderCode: order.orderId,
        customerName: order.customerName,
        phone: order.phone,
        address: order.address,
        serviceType: order.serviceType,
        status: order.status.toDbString(),
        intakeMethod: 'driver_pickup',
        fulfillmentMethod: 'delivery',
        itemCount: order.itemCount,
        intakeRecordedBy: 's-test',
        createdBy: 's-test',
      ));
}

/// Lazily-constructed placeholder DB shared by tests that don't supply repos.
/// Read-only by construction (no outbox wired), so any accidental write
/// surfaces as a `StateError` rather than silently succeeding.
AppDatabase? _placeholderDb;
AppDatabase _ensurePlaceholderDb() =>
    _placeholderDb ??= AppDatabase.forTesting(NativeDatabase.memory());

/// Builds a `DeliveryCaptureScreen` with placeholder repos for tests that only
/// exercise UI (photo picker, notes field, etc.) and never tap "Mark delivered".
DeliveryCaptureScreen _buildScreen({
  required LaundryOrder order,
  required ProofPhotoStorage storage,
  required Future<List<int>?> Function() pickPhoto,
  required DateTime Function() clock,
}) {
  return DeliveryCaptureScreen(
    order: order,
    photoStorage: storage,
    pickPhoto: pickPhoto,
    clock: clock,
    ordersRepo: OrdersRepository(_ensurePlaceholderDb()),
    proofEventsRepo: ProofEventsRepository(_ensurePlaceholderDb()),
    actorStaffId: 's-test',
    proofEventIdGenerator: () => 'pe-test',
  );
}

void main() {
  testWidgets('Mark delivered is disabled until a handover photo is captured',
      (tester) async {
    final storage = InMemoryProofPhotoStorage();
    final order = _orderReadyForDelivery();

    await tester.pumpWidget(
      MaterialApp(
        home: _buildScreen(
          order: order,
          storage: storage,
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
      'Tapping Mark delivered flips the order to completed, inserts a delivery '
      'proof_events row, and enqueues both outbox writes',
      (tester) async {
    final fixture = _DeliveryFixture.create();
    addTearDown(() async => fixture.db.close());
    final order = _orderReadyForDelivery();
    await _seedOrder(fixture.db, order);

    final storage = InMemoryProofPhotoStorage();
    bool? popResult;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    popResult = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) => DeliveryCaptureScreen(
                          order: order,
                          photoStorage: storage,
                          pickPhoto: () async => const [50, 60, 70],
                          clock: () => DateTime(2026, 5, 12, 16, 13),
                          ordersRepo: fixture.ordersRepo,
                          proofEventsRepo: fixture.proofEventsRepo,
                          actorStaffId: 's-test',
                          proofEventIdGenerator: () => 'pe-task-12',
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

    expect(popResult, isTrue);

    // Orders row was flipped to completed.
    final orderRow = await (fixture.db.select(fixture.db.orders)
          ..where((t) => t.id.equals('AMW-0421')))
        .getSingle();
    expect(orderRow.status, 'completed');

    // proof_events row landed with the right type + count + actor.
    final proofRows = await fixture.db.select(fixture.db.proofEvents).get();
    expect(proofRows, hasLength(1));
    expect(proofRows.single.id, 'pe-task-12');
    expect(proofRows.single.orderId, 'AMW-0421');
    expect(proofRows.single.type, 'delivery');
    expect(proofRows.single.itemCount, 12);
    expect(proofRows.single.capturedBy, 's-test');

    // Outbox has the proof_events insert AND the orders update.
    final outboxRows = await fixture.db.select(fixture.db.outbox).get();
    expect(outboxRows, hasLength(2));
    final tableOps = outboxRows.map((r) => '${r.forTable}:${r.op}').toSet();
    expect(
      tableOps,
      containsAll(<String>['proof_events:insert', 'orders:update']),
    );

    // Photo bytes were actually persisted to storage.
    expect(storage.savedPhotos, hasLength(1));
    expect(storage.savedPhotos.single.bytes, equals(const [50, 60, 70]));
  });

  testWidgets(
    'Mark delivered re-enables itself, surfaces an error, and lands no DB rows '
    'when photo save fails',
    (tester) async {
      final fixture = _DeliveryFixture.create();
      addTearDown(() async => fixture.db.close());
      final order = _orderReadyForDelivery();
      await _seedOrder(fixture.db, order);

      bool? popResult;
      var popResolved = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      popResult = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (_) => DeliveryCaptureScreen(
                            order: order,
                            photoStorage: _ThrowingProofPhotoStorage(),
                            pickPhoto: () async => const [50, 60, 70],
                            clock: () => DateTime(2026, 5, 12, 16, 13),
                            ordersRepo: fixture.ordersRepo,
                            proofEventsRepo: fixture.proofEventsRepo,
                            actorStaffId: 's-test',
                            proofEventIdGenerator: () => 'pe-task-12',
                          ),
                        ),
                      );
                      popResolved = true;
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

      // Push has not resolved — the screen did not pop.
      expect(popResolved, isFalse);
      expect(popResult, isNull);
      expect(find.byType(DeliveryCaptureScreen), findsOneWidget);
      // Mark-delivered button is re-enabled so the user can retry.
      final markDelivered = find.widgetWithText(
        ElevatedButton,
        'Mark delivered',
      );
      expect(
        tester.widget<ElevatedButton>(markDelivered).onPressed,
        isNotNull,
      );
      // User-facing error feedback is visible.
      expect(
        find.textContaining('Could not save delivery proof'),
        findsOneWidget,
      );
      // The exception was handled, not left dangling.
      expect(tester.takeException(), isNull);

      // Photo-save failure short-circuited before any repo write:
      // orders row still ready (for delivery), no proof_events row, no outbox rows.
      final orderRow = await (fixture.db.select(fixture.db.orders)
            ..where((t) => t.id.equals('AMW-0421')))
          .getSingle();
      expect(orderRow.status, 'ready');
      final proofRows = await fixture.db.select(fixture.db.proofEvents).get();
      expect(proofRows, isEmpty);
      final outboxRows = await fixture.db.select(fixture.db.outbox).get();
      expect(outboxRows, isEmpty);
    },
  );

  testWidgets(
    'Retrying Mark delivered after a transient status-update failure lands '
    'exactly ONE proof_events row and ONE proof_events outbox row '
    '(cached event id + persisted-flag short-circuit)',
    (tester) async {
      // Critical #2: without the cached event id + `_proofPersisted` short-
      // circuit, the second tap would either crash on a duplicate PK or land
      // a duplicate proof_events outbox row (the outbox enqueue uses a fresh
      // mutation UUID per call). With the fix the second tap only retries
      // the orders status flip.
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(() async => db.close());
      final outbox = OutboxRepository(db);
      final flakyOrdersRepo = _FlakyUpdateOrdersRepo(db, outbox: outbox);
      final proofEventsRepo = ProofEventsRepository(db, outbox: outbox);
      final order = _orderReadyForDelivery();
      await _seedOrder(db, order);

      bool? popResult;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      popResult = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (_) => DeliveryCaptureScreen(
                            order: order,
                            photoStorage: InMemoryProofPhotoStorage(),
                            pickPhoto: () async => const [50, 60, 70],
                            clock: () => DateTime(2026, 5, 12, 16, 13),
                            ordersRepo: flakyOrdersRepo,
                            proofEventsRepo: proofEventsRepo,
                            actorStaffId: 's-test',
                            proofEventIdGenerator: () => 'pe-retry-once',
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

      // First Mark delivered — proof insert succeeds, status update throws.
      await tester.tap(find.widgetWithText(ElevatedButton, 'Mark delivered'));
      await tester.pumpAndSettle();
      expect(popResult, isNull);
      expect(find.byType(DeliveryCaptureScreen), findsOneWidget);
      expect(
        find.textContaining('status update failed'),
        findsOneWidget,
      );

      var proofRows = await db.select(db.proofEvents).get();
      expect(proofRows, hasLength(1));
      expect(proofRows.single.id, 'pe-retry-once');
      var outboxRows = await db.select(db.outbox).get();
      expect(
        outboxRows.where((r) => r.forTable == 'proof_events'),
        hasLength(1),
      );
      expect(outboxRows.where((r) => r.forTable == 'orders'), isEmpty);
      var orderRow = await (db.select(db.orders)
            ..where((t) => t.id.equals('AMW-0421')))
          .getSingle();
      expect(orderRow.status, 'ready');

      // Flush the in-flight SnackBar so it doesn't overlap the button on the
      // next tap. SnackBars auto-dismiss after ~4s; pumping past that clears
      // the bottom of the screen.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      // Second tap — status update succeeds. proof_events stays at 1.
      await tester.tap(find.widgetWithText(ElevatedButton, 'Mark delivered'));
      await tester.pumpAndSettle();
      expect(popResult, isTrue);

      proofRows = await db.select(db.proofEvents).get();
      expect(proofRows, hasLength(1),
          reason:
              'cached event id + _proofPersisted must keep proof_events at exactly one row');
      expect(proofRows.single.id, 'pe-retry-once');

      outboxRows = await db.select(db.outbox).get();
      expect(
        outboxRows.where((r) => r.forTable == 'proof_events'),
        hasLength(1),
        reason:
            '_proofPersisted short-circuit must keep proof_events outbox at one row',
      );
      expect(outboxRows.where((r) => r.forTable == 'orders'), hasLength(1));

      orderRow = await (db.select(db.orders)
            ..where((t) => t.id.equals('AMW-0421')))
          .getSingle();
      expect(orderRow.status, 'completed');
    },
  );

  testWidgets(
    'Delivery falls back to itemCount when the order has no pickup proof',
    (tester) async {
      // Defensive path: scanner flow normally guarantees a pickup proof, but
      // if the screen is reached for an order without one, the delivery
      // event's count must come from itemCount rather than crash.
      final fixture = _DeliveryFixture.create();
      addTearDown(() async => fixture.db.close());

      const orderWithoutPickup = LaundryOrder(
        orderId: 'AMW-0999',
        customerName: 'No Pickup',
        serviceType: 'Wash & iron',
        status: OrderStatus.readyForDelivery,
        timeLabel: 'Today, 16:00',
        itemCount: 7,
        phone: '+234000',
        address: '5 Yaba',
        notes: '',
      );
      await _seedOrder(fixture.db, orderWithoutPickup);

      final storage = InMemoryProofPhotoStorage();

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (_) => DeliveryCaptureScreen(
                            order: orderWithoutPickup,
                            photoStorage: storage,
                            pickPhoto: () async => const [50, 60, 70],
                            clock: () => DateTime(2026, 5, 12, 16, 13),
                            ordersRepo: fixture.ordersRepo,
                            proofEventsRepo: fixture.proofEventsRepo,
                            actorStaffId: 's-test',
                            proofEventIdGenerator: () => 'pe-task-12b',
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

      // The "From pickup" panel surfaces the missing-pickup state.
      expect(find.text('No pickup proof on file.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('add_handover_photo')));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Mark delivered'));
      await tester.pumpAndSettle();

      // proof_events row carries itemCount (7) because pickupProof was null.
      final proofRows = await fixture.db.select(fixture.db.proofEvents).get();
      expect(proofRows, hasLength(1));
      expect(proofRows.single.itemCount, 7);
    },
  );

  testWidgets(
    'Captured handover photo thumbnail renders the bytes via MemoryImage',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: _buildScreen(
            order: _orderReadyForDelivery(),
            storage: InMemoryProofPhotoStorage(),
            pickPhoto: () async => const [11, 22, 33, 44],
            clock: () => DateTime(2026, 5, 12, 16, 13),
          ),
        ),
      );

      expect(find.byType(Image), findsNothing);

      await tester.tap(find.byKey(const Key('add_handover_photo')));
      await tester.pumpAndSettle();

      final images = tester.widgetList<Image>(find.byType(Image)).toList();
      expect(images, hasLength(1));
      final memoryImage = images.single.image as MemoryImage;
      expect(memoryImage.bytes, equals(Uint8List.fromList(const [11, 22, 33, 44])));
    },
  );

  testWidgets(
    'Add handover photo recovers and surfaces an error when pickPhoto throws',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: _buildScreen(
            order: _orderReadyForDelivery(),
            storage: InMemoryProofPhotoStorage(),
            pickPhoto: () async {
              throw Exception('camera permission revoked');
            },
            clock: () => DateTime(2026, 5, 12, 16, 13),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('add_handover_photo')));
      await tester.pumpAndSettle();

      // No photo was added — the tile is still available for retry.
      expect(find.byKey(const Key('add_handover_photo')), findsOneWidget);
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
    'Add handover photo surfaces a permission-specific message when camera access is denied',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: _buildScreen(
            order: _orderReadyForDelivery(),
            storage: InMemoryProofPhotoStorage(),
            pickPhoto: () async {
              throw PlatformException(code: 'camera_access_denied');
            },
            clock: () => DateTime(2026, 5, 12, 16, 13),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('add_handover_photo')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('add_handover_photo')), findsOneWidget);
      expect(find.textContaining('Camera permission denied'), findsOneWidget);
      expect(find.textContaining('Settings'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Add handover photo surfaces a device-specific message when no camera is available',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: _buildScreen(
            order: _orderReadyForDelivery(),
            storage: InMemoryProofPhotoStorage(),
            pickPhoto: () async {
              throw PlatformException(code: 'no_available_camera');
            },
            clock: () => DateTime(2026, 5, 12, 16, 13),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('add_handover_photo')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('add_handover_photo')), findsOneWidget);
      expect(find.textContaining('No camera'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Rapid taps on add handover photo only trigger one pickPhoto and hide the tile',
    (tester) async {
      final completers = <Completer<List<int>?>>[];

      await tester.pumpWidget(
        MaterialApp(
          home: _buildScreen(
            order: _orderReadyForDelivery(),
            storage: InMemoryProofPhotoStorage(),
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
