import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:amuwak_staff/src/orders/order.dart';
import 'package:amuwak_staff/src/orders/order_status.dart';
import 'package:amuwak_staff/src/orders/proof/pickup_capture_screen.dart';
import 'package:amuwak_staff/src/orders/proof/proof_photo_storage.dart';
import 'package:amuwak_staff/src/orders/proof_event.dart';
import 'package:amuwak_staff/src/orders/service_type.dart';
import 'package:amuwak_staff/src/sync/orders_repository.dart';
import 'package:amuwak_staff/src/sync/proof_events_repository.dart';

/// Online-only mode: PickupCaptureScreen takes Supabase-backed repos via its
/// constructor. These tests mock them — UI-only cases use mocks that are never
/// called; write-path cases stub `insertEvent` / `updateStatus` and verify what
/// the screen passed (replacing the old in-memory-Drift row + outbox inspection).
/// The repo's own idempotency (upsert on the proof-event PK) is its contract;
/// here we verify the *screen* reuses a cached event id across retries.
class _MockOrdersRepository extends Mock implements OrdersRepository {}

class _MockProofEventsRepository extends Mock
    implements ProofEventsRepository {}

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
  serviceType: ServiceType.washAndIron,
  status: OrderStatus.pendingPickup,
  timeLabel: 'Today, 09:00',
  itemCount: 12,
  phone: '+234000',
  address: '5 Yaba',
  notes: 'Gate locked',
);

/// A mock OrdersRepository whose `updateStatus` throws on the first call and
/// succeeds thereafter — exercises the capture-screen retry path.
_MockOrdersRepository _flakyUpdateOrdersRepo() {
  final repo = _MockOrdersRepository();
  var calls = 0;
  when(() => repo.updateStatus(any(), any(),
      actorStaffId: any(named: 'actorStaffId'),
      updatedAt: any(named: 'updatedAt'))).thenAnswer((_) async {
    calls += 1;
    if (calls == 1) throw Exception('transient flake');
  });
  return repo;
}

/// Fresh mock repos with write methods stubbed to succeed.
_MockOrdersRepository _okOrdersRepo() {
  final repo = _MockOrdersRepository();
  when(() => repo.updateStatus(any(), any(),
          actorStaffId: any(named: 'actorStaffId'),
          updatedAt: any(named: 'updatedAt')))
      .thenAnswer((_) async {});
  return repo;
}

_MockProofEventsRepository _okProofRepo() {
  final repo = _MockProofEventsRepository();
  when(() => repo.insertEvent(any(),
          orderId: any(named: 'orderId'),
          actorStaffId: any(named: 'actorStaffId')))
      .thenAnswer((_) async {});
  return repo;
}

PickupCaptureScreen _buildScreen({
  required LaundryOrder order,
  required ProofPhotoStorage storage,
  required Future<List<int>?> Function() pickPhoto,
  required DateTime Function() clock,
  OrdersRepository? ordersRepo,
  ProofEventsRepository? proofEventsRepo,
}) {
  return PickupCaptureScreen(
    order: order,
    photoStorage: storage,
    pickPhoto: pickPhoto,
    clock: clock,
    ordersRepo: ordersRepo ?? _okOrdersRepo(),
    proofEventsRepo: proofEventsRepo ?? _okProofRepo(),
    actorStaffId: 's-test',
    proofEventIdGenerator: () => 'pe-test',
  );
}

Future<bool?> _pumpAndPushPickup(
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
  final handle = _PopHandle();
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          return Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  handle.result = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => PickupCaptureScreen(
                        order: order,
                        photoStorage: storage,
                        pickPhoto: pickPhoto ?? () async => const [1, 2, 3, 4],
                        clock: clock ?? () => DateTime(2026, 5, 12, 9, 42),
                        ordersRepo: ordersRepo ?? _okOrdersRepo(),
                        proofEventsRepo: proofEventsRepo ?? _okProofRepo(),
                        actorStaffId: actorStaffId,
                        proofEventIdGenerator:
                            proofEventIdGenerator ?? () => 'pe-test',
                      ),
                    ),
                  );
                  handle.resolved = true;
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
  // Stash the handle on the tester via an expando-free approach: return it.
  _lastHandle = handle;
  return handle.result;
}

/// Most-recent push handle so write-path tests can read the pop result/resolved
/// flag after driving the screen.
_PopHandle? _lastHandle;

void main() {
  setUpAll(() {
    registerFallbackValue(ProofEvent(
      id: 'fb',
      type: ProofEventType.pickup,
      capturedAt: DateTime(2026, 1, 1),
      count: 1,
      photoPaths: const [],
    ));
    registerFallbackValue(OrderStatus.pendingPickup);
    registerFallbackValue(DateTime(2026, 1, 1));
  });

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

    await tester.tap(find.byKey(const Key('count_increment')));
    await tester.pump();
    expect(tester.widget<ElevatedButton>(confirmButton).onPressed, isNull);

    await tester.tap(find.byKey(const Key('add_photo')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<ElevatedButton>(confirmButton).onPressed,
      isNotNull,
    );
  });

  testWidgets(
      'Tapping Done flips the order to in_progress and inserts a pickup '
      'proof event through the repos', (tester) async {
    final ordersRepo = _okOrdersRepo();
    final proofEventsRepo = _okProofRepo();
    final storage = InMemoryProofPhotoStorage();

    await _pumpAndPushPickup(
      tester,
      storage: storage,
      order: _baseOrder,
      pickPhoto: () async => const [10, 20, 30],
      ordersRepo: ordersRepo,
      proofEventsRepo: proofEventsRepo,
      proofEventIdGenerator: () => 'pe-task-11',
    );

    for (var i = 0; i < 12; i++) {
      await tester.tap(find.byKey(const Key('count_increment')));
      await tester.pump();
    }
    await tester.tap(find.byKey(const Key('add_photo')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(ElevatedButton, 'Confirm with customer'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Tie tag to the bag'), findsOneWidget);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Done'));
    await tester.pumpAndSettle();

    expect(_lastHandle!.result, isTrue);

    // Proof event inserted with the right id/type/count/orderId.
    final event = verify(() => proofEventsRepo.insertEvent(
          captureAny(),
          orderId: 'AMW-0421',
          actorStaffId: 's-test',
        )).captured.single as ProofEvent;
    expect(event.id, 'pe-task-11');
    expect(event.type, ProofEventType.pickup);
    expect(event.count, 12);

    // Order flipped to in_progress through the repo.
    verify(() => ordersRepo.updateStatus(
          'AMW-0421',
          OrderStatus.inProgress,
          actorStaffId: 's-test',
          updatedAt: any(named: 'updatedAt'),
        )).called(1);

    // Photo bytes were persisted to storage.
    expect(storage.savedPhotos, hasLength(1));
    expect(storage.savedPhotos.single.bytes, equals(const [10, 20, 30]));
  });

  testWidgets(
    'Done re-enables itself, surfaces an error, and performs NO repo writes '
    'when photo save fails',
    (tester) async {
      final ordersRepo = _okOrdersRepo();
      final proofEventsRepo = _okProofRepo();

      await _pumpAndPushPickup(
        tester,
        storage: _ThrowingProofPhotoStorage(),
        order: _baseOrder,
        pickPhoto: () async => const [10, 20, 30],
        ordersRepo: ordersRepo,
        proofEventsRepo: proofEventsRepo,
        proofEventIdGenerator: () => 'pe-task-11',
      );

      await tester.tap(find.byKey(const Key('count_increment')));
      await tester.tap(find.byKey(const Key('add_photo')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(ElevatedButton, 'Confirm with customer'),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ElevatedButton, 'Done'));
      await tester.pumpAndSettle();

      // Did not pop; still on QR stage; Done re-enabled; error shown.
      expect(_lastHandle!.resolved, isFalse);
      expect(_lastHandle!.result, isNull);
      expect(find.text('Tie tag to the bag'), findsOneWidget);
      final done = find.widgetWithText(ElevatedButton, 'Done');
      expect(tester.widget<ElevatedButton>(done).onPressed, isNotNull);
      expect(find.textContaining('Could not save pickup proof'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Photo-save failure short-circuited before any repo write.
      verifyNever(() => proofEventsRepo.insertEvent(any(),
          orderId: any(named: 'orderId'),
          actorStaffId: any(named: 'actorStaffId')));
      verifyNever(() => ordersRepo.updateStatus(any(), any(),
          actorStaffId: any(named: 'actorStaffId'),
          updatedAt: any(named: 'updatedAt')));
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
      for (var i = 0; i < 5; i++) {
        await tester.tap(addTile);
      }
      await tester.pump();

      expect(completers, hasLength(1));
      expect(find.byKey(const Key('add_photo')), findsNothing);

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

      expect(find.byKey(const Key('add_photo')), findsOneWidget);
      expect(find.textContaining('Could not open camera'), findsOneWidget);
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
    'Retrying Done after a transient status-update failure reuses the cached '
    'proof-event id (so the repo upsert stays idempotent)',
    (tester) async {
      // Critical #2: a fresh UUID per Done-tap would land a duplicate proof
      // event on retry. The screen caches the id, so both insertEvent calls
      // use the SAME id and the repo's upsert dedupes server-side.
      final flakyOrdersRepo = _flakyUpdateOrdersRepo();
      final proofEventsRepo = _okProofRepo();

      await _pumpAndPushPickup(
        tester,
        storage: InMemoryProofPhotoStorage(),
        order: _baseOrder,
        pickPhoto: () async => const [10, 20, 30],
        ordersRepo: flakyOrdersRepo,
        proofEventsRepo: proofEventsRepo,
        proofEventIdGenerator: () => 'pe-retry-once',
      );

      await tester.tap(find.byKey(const Key('count_increment')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('add_photo')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(ElevatedButton, 'Confirm with customer'),
      );
      await tester.pumpAndSettle();

      // First Done — proof insert succeeds, status update throws → no pop.
      await tester.tap(find.widgetWithText(ElevatedButton, 'Done'));
      await tester.pumpAndSettle();
      expect(_lastHandle!.result, isNull);
      expect(find.text('Tie tag to the bag'), findsOneWidget);
      expect(find.textContaining('status update failed'), findsOneWidget);

      // Flush the SnackBar before tapping Done again.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      // Second Done — status update succeeds → pops.
      await tester.tap(find.widgetWithText(ElevatedButton, 'Done'));
      await tester.pumpAndSettle();
      expect(_lastHandle!.result, isTrue);

      // insertEvent was called on BOTH taps with the SAME cached id.
      final events = verify(() => proofEventsRepo.insertEvent(
            captureAny(),
            orderId: 'AMW-0421',
            actorStaffId: 's-test',
          )).captured.cast<ProofEvent>();
      expect(events, hasLength(2));
      expect(events.every((e) => e.id == 'pe-retry-once'), isTrue);

      // updateStatus attempted twice (first threw, second succeeded).
      verify(() => flakyOrdersRepo.updateStatus(
            'AMW-0421',
            OrderStatus.inProgress,
            actorStaffId: 's-test',
            updatedAt: any(named: 'updatedAt'),
          )).called(2);
    },
  );

  testWidgets(
    'Back from QR stage returns to collecting without losing count/photos/notes',
    (tester) async {
      final storage = InMemoryProofPhotoStorage();

      await _pumpAndPushPickup(
        tester,
        storage: storage,
        order: _baseOrder,
        pickPhoto: () async => const [10, 20, 30],
      );

      for (var i = 0; i < 7; i++) {
        await tester.tap(find.byKey(const Key('count_increment')));
        await tester.pump();
      }
      await tester.tap(find.byKey(const Key('add_photo')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'fragile silk');
      await tester.pump();

      await tester.tap(
        find.widgetWithText(ElevatedButton, 'Confirm with customer'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Tie tag to the bag'), findsOneWidget);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(_lastHandle!.resolved, isFalse);
      expect(_lastHandle!.result, isNull);
      expect(find.text('Tie tag to the bag'), findsNothing);
      expect(find.text('Confirm with customer'), findsOneWidget);

      expect(find.text('7'), findsOneWidget);
      expect(find.text('Photos (1/3)'), findsOneWidget);
      expect(find.text('fragile silk'), findsOneWidget);
    },
  );
}

/// Mutable holder for a pushed route's pop result + whether the push resolved.
class _PopHandle {
  bool? result;
  bool resolved = false;
}
