import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Hide Drift's row class `ProofEvent` so the tests can keep referring to the
// domain `ProofEvent` from `orders/proof_event.dart` without ambiguity.
import 'package:amuwak_staff/src/data/app_database.dart' hide ProofEvent;
import 'package:amuwak_staff/src/orders/order.dart';
import 'package:amuwak_staff/src/orders/order_status.dart';
import 'package:amuwak_staff/src/orders/proof/pickup_capture_screen.dart';
import 'package:amuwak_staff/src/orders/proof/proof_photo_storage.dart';
import 'package:amuwak_staff/src/orders/proof_event.dart';
import 'package:amuwak_staff/src/orders/service_type.dart';
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
/// first call and delegate to the real repo on subsequent calls. Used to
/// exercise the capture-screen retry path: insert proof succeeds, status
/// update fails, user retries, status update succeeds.
class _FlakyUpdateOrdersRepo extends OrdersRepository {
  _FlakyUpdateOrdersRepo(super.db, {required super.outbox});

  int _calls = 0;

  @override
  Future<void> updateStatus(
    String orderId,
    OrderStatus newStatus, {
    required String actorStaffId,
    DateTime? updatedAt,
  }) async {
    _calls += 1;
    if (_calls == 1) {
      throw Exception('transient flake');
    }
    return super.updateStatus(
      orderId,
      newStatus,
      actorStaffId: actorStaffId,
      updatedAt: updatedAt,
    );
  }
}

const _baseOrder = LaundryOrder(
  orderId: 'AMW-0421',
  customerName: 'Jane Doe',
  serviceType: ServiceType.washAndIron,
  status: OrderStatus.pendingPickup,
  timeLabel: 'Today, 09:00',
  itemCount: 12,
  phone: '+234000',
  address: '5 Yaba',
  notes: 'Gate locked',
);

/// Bundles an in-memory Drift DB + outbox + wired repos for tests that need
/// to assert the write path lands the right rows.
class _PickupFixture {
  _PickupFixture._(this.db, this.outbox, this.ordersRepo, this.proofEventsRepo);

  final AppDatabase db;
  final OutboxRepository outbox;
  final OrdersRepository ordersRepo;
  final ProofEventsRepository proofEventsRepo;

  static _PickupFixture create() {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final outbox = OutboxRepository(db);
    final ordersRepo = OrdersRepository(
      db,
      outbox: outbox,
      clock: () => DateTime.utc(2026, 5, 21, 12, 0),
    );
    final proofEventsRepo = ProofEventsRepository(
      db,
      outbox: outbox,
      clock: () => DateTime.utc(2026, 5, 21, 12, 0),
    );
    return _PickupFixture._(db, outbox, ordersRepo, proofEventsRepo);
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
        serviceType: order.serviceType.toDbString(),
        status: order.status.toDbString(),
        intakeMethod: 'driver_pickup',
        fulfillmentMethod: 'delivery',
        itemCount: order.itemCount,
        intakeRecordedBy: 's-test',
        createdBy: 's-test',
      ));
}

/// Lazily-constructed placeholder DB shared by `_pumpAndPushPickup` calls that
/// don't supply repos. Read-only by construction (no outbox wired), so any
/// accidental write surfaces as a `StateError` rather than silently succeeding.
AppDatabase? _placeholderDb;
AppDatabase _ensurePlaceholderDb() =>
    _placeholderDb ??= AppDatabase.forTesting(NativeDatabase.memory());

/// Builds a `PickupCaptureScreen` with the placeholder repos for tests that
/// only exercise UI (count buttons, photo picker, etc.) and never tap "Done".
PickupCaptureScreen _buildScreen({
  required LaundryOrder order,
  required ProofPhotoStorage storage,
  required Future<List<int>?> Function() pickPhoto,
  required DateTime Function() clock,
}) {
  return PickupCaptureScreen(
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

Future<void> _pumpAndPushPickup(
  WidgetTester tester, {
  required ProofPhotoStorage storage,
  required LaundryOrder order,
  Future<List<int>?> Function()? pickPhoto,
  DateTime Function()? clock,
  OrdersRepository? ordersRepo,
  ProofEventsRepository? proofEventsRepo,
  String actorStaffId = 's-test',
  String Function()? proofEventIdGenerator,
}) async {
  final effectiveOrdersRepo =
      ordersRepo ?? OrdersRepository(_ensurePlaceholderDb());
  final effectiveProofEventsRepo =
      proofEventsRepo ?? ProofEventsRepository(_ensurePlaceholderDb());
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
                      builder: (_) => PickupCaptureScreen(
                        order: order,
                        photoStorage: storage,
                        pickPhoto:
                            pickPhoto ?? () async => const [1, 2, 3, 4],
                        clock: clock ?? () => DateTime(2026, 5, 12, 9, 42),
                        ordersRepo: effectiveOrdersRepo,
                        proofEventsRepo: effectiveProofEventsRepo,
                        actorStaffId: actorStaffId,
                        proofEventIdGenerator:
                            proofEventIdGenerator ?? () => 'pe-test',
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
      'Tapping Done flips the order to in_progress, inserts a pickup '
      'proof_events row, and enqueues both outbox writes',
      (tester) async {
    final fixture = _PickupFixture.create();
    addTearDown(() async => fixture.db.close());
    await _seedOrder(fixture.db, _baseOrder);

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
                        builder: (_) => PickupCaptureScreen(
                          order: _baseOrder,
                          photoStorage: storage,
                          pickPhoto: () async => const [10, 20, 30],
                          clock: () => DateTime(2026, 5, 12, 9, 42),
                          ordersRepo: fixture.ordersRepo,
                          proofEventsRepo: fixture.proofEventsRepo,
                          actorStaffId: 's-test',
                          proofEventIdGenerator: () => 'pe-task-11',
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

    // Tap Done → screen pops once both writes resolve.
    await tester.tap(find.widgetWithText(ElevatedButton, 'Done'));
    await tester.pumpAndSettle();

    expect(popResult, isTrue);

    // Orders row was flipped to in_progress.
    final orderRow = await (fixture.db.select(fixture.db.orders)
          ..where((t) => t.id.equals('AMW-0421')))
        .getSingle();
    expect(orderRow.status, 'in_progress');

    // proof_events row landed with the right type + count + actor.
    final proofRows = await fixture.db.select(fixture.db.proofEvents).get();
    expect(proofRows, hasLength(1));
    expect(proofRows.single.id, 'pe-task-11');
    expect(proofRows.single.orderId, 'AMW-0421');
    expect(proofRows.single.type, 'pickup');
    expect(proofRows.single.itemCount, 12);
    expect(proofRows.single.capturedBy, 's-test');

    // Outbox has the proof_events insert AND the orders update.
    final outboxRows = await fixture.db.select(fixture.db.outbox).get();
    expect(outboxRows, hasLength(2));
    final tableOps = outboxRows
        .map((r) => '${r.forTable}:${r.op}')
        .toSet();
    expect(
      tableOps,
      containsAll(<String>['proof_events:insert', 'orders:update']),
    );

    // Photo bytes were actually persisted to storage.
    expect(storage.savedPhotos, hasLength(1));
    expect(storage.savedPhotos.single.bytes, equals(const [10, 20, 30]));
  });

  testWidgets(
    'Done re-enables itself, surfaces an error, and lands no DB rows '
    'when photo save fails',
    (tester) async {
      final fixture = _PickupFixture.create();
      addTearDown(() async => fixture.db.close());
      await _seedOrder(fixture.db, _baseOrder);

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
                          builder: (_) => PickupCaptureScreen(
                            order: _baseOrder,
                            photoStorage: _ThrowingProofPhotoStorage(),
                            pickPhoto: () async => const [10, 20, 30],
                            clock: () => DateTime(2026, 5, 12, 9, 42),
                            ordersRepo: fixture.ordersRepo,
                            proofEventsRepo: fixture.proofEventsRepo,
                            actorStaffId: 's-test',
                            proofEventIdGenerator: () => 'pe-task-11',
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
      expect(popResolved, isFalse);
      expect(popResult, isNull);
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

      // Photo-save failure short-circuited before any repo write:
      // orders row still pending_pickup, no proof_events row, no outbox rows.
      final orderRow = await (fixture.db.select(fixture.db.orders)
            ..where((t) => t.id.equals('AMW-0421')))
          .getSingle();
      expect(orderRow.status, 'pending_pickup');
      final proofRows = await fixture.db.select(fixture.db.proofEvents).get();
      expect(proofRows, isEmpty);
      final outboxRows = await fixture.db.select(fixture.db.outbox).get();
      expect(outboxRows, isEmpty);
    },
  );

  testWidgets(
    'Rapid taps on add photo only trigger one pickPhoto and hide the tile',
    (tester) async {
      final completers = <Completer<List<int>?>>[];

      await tester.pumpWidget(
        MaterialApp(
          home: _buildScreen(
            order: _baseOrder,
            storage: InMemoryProofPhotoStorage(),
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
          home: _buildScreen(
            order: _baseOrder,
            storage: InMemoryProofPhotoStorage(),
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
          home: _buildScreen(
            order: _baseOrder,
            storage: InMemoryProofPhotoStorage(),
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
    'Add photo surfaces a permission-specific message when camera access is denied',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: _buildScreen(
            order: _baseOrder,
            storage: InMemoryProofPhotoStorage(),
            pickPhoto: () async {
              throw PlatformException(code: 'camera_access_denied');
            },
            clock: () => DateTime(2026, 5, 12, 9, 42),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('add_photo')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('add_photo')), findsOneWidget);
      expect(find.textContaining('Camera permission denied'), findsOneWidget);
      expect(find.textContaining('Settings'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Add photo surfaces a device-specific message when no camera is available',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: _buildScreen(
            order: _baseOrder,
            storage: InMemoryProofPhotoStorage(),
            pickPhoto: () async {
              throw PlatformException(code: 'no_available_camera');
            },
            clock: () => DateTime(2026, 5, 12, 9, 42),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('add_photo')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('add_photo')), findsOneWidget);
      expect(find.textContaining('No camera'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Retrying Done after a transient status-update failure lands exactly ONE '
    'proof_events row and ONE proof_events outbox row (cached event id)',
    (tester) async {
      // Critical #2: a fresh UUID per Done-tap would otherwise land a second
      // proof_events row and outbox enqueue on every retry. With caching, the
      // proof_events insertOrIgnore is a no-op on the second tap and only the
      // orders update runs.
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(() async => db.close());
      final outbox = OutboxRepository(db);
      final flakyOrdersRepo = _FlakyUpdateOrdersRepo(
        db,
        outbox: outbox,
      );
      final proofEventsRepo = ProofEventsRepository(db, outbox: outbox);
      await _seedOrder(db, _baseOrder);

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
                          builder: (_) => PickupCaptureScreen(
                            order: _baseOrder,
                            photoStorage: InMemoryProofPhotoStorage(),
                            pickPhoto: () async => const [10, 20, 30],
                            clock: () => DateTime(2026, 5, 12, 9, 42),
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

      // Set count + photo and confirm to reach the QR stage.
      await tester.tap(find.byKey(const Key('count_increment')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('add_photo')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(ElevatedButton, 'Confirm with customer'),
      );
      await tester.pumpAndSettle();

      // First Done — proof insert succeeds, status update throws. Screen does
      // NOT pop, error SnackBar surfaces.
      await tester.tap(find.widgetWithText(ElevatedButton, 'Done'));
      await tester.pumpAndSettle();
      expect(popResult, isNull);
      expect(find.text('Tie tag to the bag'), findsOneWidget);
      expect(
        find.textContaining('status update failed'),
        findsOneWidget,
      );

      // After the first tap, exactly one proof_events row and one outbox row.
      var proofRows = await db.select(db.proofEvents).get();
      expect(proofRows, hasLength(1));
      expect(proofRows.single.id, 'pe-retry-once');
      var outboxRows = await db.select(db.outbox).get();
      expect(outboxRows.where((r) => r.forTable == 'proof_events'), hasLength(1));
      // No successful orders update yet.
      expect(outboxRows.where((r) => r.forTable == 'orders'), isEmpty);
      var orderRow = await (db.select(db.orders)
            ..where((t) => t.id.equals('AMW-0421')))
          .getSingle();
      expect(orderRow.status, 'pending_pickup');

      // Flush the in-flight SnackBar so it doesn't overlap the Done button
      // on the next tap. SnackBars auto-dismiss after ~4s by default;
      // pumping forward past that and settling clears the bottom of the
      // screen.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      // Second Done — status update succeeds. proof_events stays at 1 (cached
      // event id + insertOrIgnore). Orders status flips, orders outbox row
      // lands. Screen pops.
      await tester.tap(find.widgetWithText(ElevatedButton, 'Done'));
      await tester.pumpAndSettle();
      expect(popResult, isTrue);

      proofRows = await db.select(db.proofEvents).get();
      expect(proofRows, hasLength(1),
          reason: 'cached event id must keep proof_events at exactly one row');
      expect(proofRows.single.id, 'pe-retry-once');

      outboxRows = await db.select(db.outbox).get();
      expect(outboxRows.where((r) => r.forTable == 'proof_events'), hasLength(1),
          reason: 'cached event id must keep proof_events outbox at one row');
      expect(outboxRows.where((r) => r.forTable == 'orders'), hasLength(1));

      orderRow = await (db.select(db.orders)
            ..where((t) => t.id.equals('AMW-0421')))
          .getSingle();
      expect(orderRow.status, 'in_progress');
    },
  );

  testWidgets(
    'Back from QR stage returns to collecting without losing count/photos/notes',
    (tester) async {
      final storage = InMemoryProofPhotoStorage();
      bool? captured;
      var poppedFromPush = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      captured = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (_) => _buildScreen(
                            order: _baseOrder,
                            storage: storage,
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
