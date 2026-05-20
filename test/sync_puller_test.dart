import 'package:drift/drift.dart' show OrderingTerm;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:amuwak_staff/src/data/app_database.dart';
import 'package:amuwak_staff/src/sync/sync_puller.dart';
import 'package:amuwak_staff/src/sync/sync_registry.dart';

class _FakeFetch {
  /// Map of (table name) -> sequence of result batches. Each call to fetch
  /// consumes one batch from the head of the list.
  final Map<String, List<List<Map<String, dynamic>>>> queued = {};

  /// Records the `since` value the puller passed for each call.
  final List<MapEntry<String, DateTime>> sinceCalls = [];

  Future<List<Map<String, dynamic>>> call(SyncTable table, DateTime since) async {
    sinceCalls.add(MapEntry(table.name, since));
    final q = queued[table.name];
    if (q == null || q.isEmpty) return const [];
    return q.removeAt(0);
  }
}

const _customers = SyncTable(name: 'customers');

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async => db.close());

  test('pullTable upserts returned rows and advances the watermark', () async {
    final fake = _FakeFetch();
    fake.queued['customers'] = [
      [
        {
          'id': 'c-1', 'name': 'Alice', 'phone': '+254700',
          'address': null, 'notes': null,
          'created_at': '2026-05-19T10:00:00Z',
          'updated_at': '2026-05-19T10:00:00Z',
          'deleted_at': null,
        },
        {
          'id': 'c-2', 'name': 'Bob', 'phone': '+254701',
          'address': null, 'notes': null,
          'created_at': '2026-05-19T11:00:00Z',
          'updated_at': '2026-05-19T11:00:00Z',
          'deleted_at': null,
        },
      ],
    ];

    final puller = SyncPuller(db: db, fetch: fake.call);
    final pulled = await puller.pullTable(_customers);

    expect(pulled, 2);

    final localRows = await db.select(db.customers).get()
      ..sort((a, b) => a.id.compareTo(b.id));
    expect(localRows, hasLength(2));
    expect(localRows.first.name, 'Alice');
    expect(localRows[1].name, 'Bob');

    // Watermark advanced to the max updated_at it saw
    final wm = await (db.select(db.syncWatermarks)
          ..where((t) => t.forTable.equals('customers')))
        .getSingle();
    expect(wm.lastSyncedAt.toUtc().toIso8601String(),
        '2026-05-19T11:00:00.000Z');

    // First call asked since-epoch
    expect(fake.sinceCalls.first.value.year, 1970);
  });

  test('pullTable passes the existing watermark on the next call', () async {
    final fake = _FakeFetch();
    fake.queued['customers'] = [
      [
        {
          'id': 'c-1', 'name': 'Alice', 'phone': '+254',
          'address': null, 'notes': null,
          'created_at': '2026-05-19T10:00:00Z',
          'updated_at': '2026-05-19T10:00:00Z',
          'deleted_at': null,
        },
      ],
      const [],
    ];

    final puller = SyncPuller(db: db, fetch: fake.call);

    await puller.pullTable(_customers);
    final pulled2 = await puller.pullTable(_customers);

    expect(pulled2, 0);
    expect(fake.sinceCalls, hasLength(2));
    expect(fake.sinceCalls[1].value.toUtc().toIso8601String(),
        '2026-05-19T10:00:00.000Z');
  });

  test('pullTable advances the watermark from the configured column', () async {
    // Plan 3a Task 6: prove the puller uses `SyncTable.watermarkColumn`
    // instead of hard-coding `updated_at`. The fixture row deliberately
    // sets `created_at` later than `updated_at` — if the puller reads
    // the right column, the watermark lands on the `created_at` value.
    final fake = _FakeFetch();
    fake.queued['customers'] = [
      [
        {
          'id': 'c-1', 'name': 'Alice', 'phone': '+254',
          'address': null, 'notes': null,
          'created_at': '2026-05-19T12:00:00Z',
          'updated_at': '2026-05-19T08:00:00Z',
          'deleted_at': null,
        },
      ],
    ];

    final puller = SyncPuller(db: db, fetch: fake.call);
    await puller.pullTable(
      const SyncTable(name: 'customers', watermarkColumn: 'created_at'),
    );

    final wm = await (db.select(db.syncWatermarks)
          ..where((t) => t.forTable.equals('customers')))
        .getSingle();
    expect(wm.lastSyncedAt.toUtc().toIso8601String(),
        '2026-05-19T12:00:00.000Z');
  });

  group('Plan 3a Task 7 mappers — additional tables', () {
    test('pullTable upserts order_status_events rows '
        '(including null from_status and null device_event_id)', () async {
      final fake = _FakeFetch();
      fake.queued['order_status_events'] = [
        [
          {
            'id': 'se-1',
            'order_id': 'AMW-A',
            'from_status': null,
            'to_status': 'pending_pickup',
            'changed_by': 's-1',
            'changed_at': '2026-05-19T09:00:00Z',
            'source': 'mobile',
            'device_event_id': null,
          },
          {
            'id': 'se-2',
            'order_id': 'AMW-A',
            'from_status': 'pending_pickup',
            'to_status': 'received',
            'changed_by': 's-1',
            'changed_at': '2026-05-19T11:00:00Z',
            'source': 'mobile',
            'device_event_id': 'dev-evt-1',
          },
        ],
      ];

      final puller = SyncPuller(db: db, fetch: fake.call);
      final pulled = await puller.pullTable(const SyncTable(
        name: 'order_status_events',
        watermarkColumn: 'changed_at',
      ));

      expect(pulled, 2);
      final rows = await (db.select(db.orderStatusEvents)
            ..orderBy([(t) => OrderingTerm(expression: t.changedAt)]))
          .get();
      expect(rows.map((r) => r.id).toList(), ['se-1', 'se-2']);
      expect(rows[0].fromStatus, isNull);
      expect(rows[0].deviceEventId, isNull);
      expect(rows[1].fromStatus, 'pending_pickup');
      expect(rows[1].deviceEventId, 'dev-evt-1');
    });

    test('pullTable upserts proof_photos rows '
        '(including null width/height/bytes/uploaded_at)', () async {
      final fake = _FakeFetch();
      fake.queued['proof_photos'] = [
        [
          {
            'id': 'pp-1',
            'proof_event_id': 'pe-1',
            'storage_path': 'proofs/pp-1.jpg',
            'width': null,
            'height': null,
            'bytes': null,
            'uploaded_at': null,
            'created_at': '2026-05-19T10:30:00Z',
          },
          {
            'id': 'pp-2',
            'proof_event_id': 'pe-1',
            'storage_path': 'proofs/pp-2.jpg',
            'width': 1024,
            'height': 768,
            'bytes': 102400,
            'uploaded_at': '2026-05-19T10:35:00Z',
            'created_at': '2026-05-19T10:31:00Z',
          },
        ],
      ];

      final puller = SyncPuller(db: db, fetch: fake.call);
      final pulled = await puller.pullTable(const SyncTable(
        name: 'proof_photos',
        watermarkColumn: 'created_at',
      ));

      expect(pulled, 2);
      final rows = await (db.select(db.proofPhotos)
            ..orderBy([(t) => OrderingTerm(expression: t.id)]))
          .get();
      expect(rows.map((r) => r.id).toList(), ['pp-1', 'pp-2']);
      expect(rows[0].width, isNull);
      expect(rows[0].uploadedAt, isNull);
      expect(rows[1].width, 1024);
      expect(rows[1].height, 768);
      expect(rows[1].bytes, 102400);
      expect(rows[1].uploadedAt, isNotNull);
    });

    test('pullTable upserts issues rows '
        '(including null order_id / resolved_at / resolved_by)', () async {
      final fake = _FakeFetch();
      // Synthetic `updated_at` (not present in the live Postgres schema until
      // a future migration adds it) keeps the watermark math happy; the
      // mapper ignores it.
      fake.queued['issues'] = [
        [
          {
            'id': 'iss-1',
            'order_id': null,
            'kind': 'missing_item',
            'description': 'Missing one sock',
            'reported_by': 's-1',
            'reported_at': '2026-05-19T12:00:00Z',
            'resolved_at': null,
            'resolved_by': null,
            'updated_at': '2026-05-19T12:00:00Z',
          },
          {
            'id': 'iss-2',
            'order_id': 'AMW-A',
            'kind': 'damaged',
            'description': 'Stain found after wash',
            'reported_by': 's-1',
            'reported_at': '2026-05-19T13:00:00Z',
            'resolved_at': '2026-05-19T15:00:00Z',
            'resolved_by': 's-2',
            'updated_at': '2026-05-19T15:00:00Z',
          },
        ],
      ];

      final puller = SyncPuller(db: db, fetch: fake.call);
      final pulled = await puller.pullTable(const SyncTable(name: 'issues'));

      expect(pulled, 2);
      final rows = await (db.select(db.issues)
            ..orderBy([(t) => OrderingTerm(expression: t.id)]))
          .get();
      expect(rows.map((r) => r.id).toList(), ['iss-1', 'iss-2']);
      expect(rows[0].orderId, isNull);
      expect(rows[0].resolvedAt, isNull);
      expect(rows[0].resolvedBy, isNull);
      expect(rows[1].orderId, 'AMW-A');
      expect(rows[1].resolvedAt, isNotNull);
      expect(rows[1].resolvedBy, 's-2');
    });

    test('pullTable upserts shifts rows '
        '(including null lat/lng/ended_at)', () async {
      final fake = _FakeFetch();
      fake.queued['shifts'] = [
        [
          {
            'id': 'sh-1',
            'staff_id': 's-1',
            'started_at': '2026-05-19T08:00:00Z',
            'started_lat': null,
            'started_lng': null,
            'ended_at': null,
            'ended_lat': null,
            'ended_lng': null,
            'updated_at': '2026-05-19T08:00:00Z',
          },
          {
            'id': 'sh-2',
            'staff_id': 's-2',
            'started_at': '2026-05-19T09:00:00Z',
            'started_lat': 0.3476,
            'started_lng': 32.5825,
            'ended_at': '2026-05-19T17:00:00Z',
            'ended_lat': 0.3500,
            'ended_lng': 32.5800,
            'updated_at': '2026-05-19T17:00:00Z',
          },
        ],
      ];

      final puller = SyncPuller(db: db, fetch: fake.call);
      final pulled = await puller.pullTable(const SyncTable(name: 'shifts'));

      expect(pulled, 2);
      final rows = await (db.select(db.shifts)
            ..orderBy([(t) => OrderingTerm(expression: t.id)]))
          .get();
      expect(rows.map((r) => r.id).toList(), ['sh-1', 'sh-2']);
      expect(rows[0].startedLat, isNull);
      expect(rows[0].endedAt, isNull);
      expect(rows[1].startedLat, closeTo(0.3476, 1e-6));
      expect(rows[1].endedLng, closeTo(32.5800, 1e-6));
      expect(rows[1].endedAt, isNotNull);
    });

    test('pullTable upserts valid_transitions rows '
        '(including null from_status for initial states)', () async {
      // valid_transitions is static seed; ValidTransitionsLoader (Task 9)
      // is the production caller. This test exercises the same mapper
      // through pullTable with a synthetic watermark column so we can
      // verify the upsert path works.
      final fake = _FakeFetch();
      fake.queued['valid_transitions'] = [
        [
          {
            'id': 'vt-1',
            'intake_method': 'walk_in',
            'fulfillment_method': 'customer_collect',
            'from_status': null,
            'to_status': 'received',
            'created_at': '2026-05-19T08:00:00Z',
          },
          {
            'id': 'vt-2',
            'intake_method': 'driver_pickup',
            'fulfillment_method': 'delivery',
            'from_status': 'ready',
            'to_status': 'out_for_delivery',
            'created_at': '2026-05-19T08:00:00Z',
          },
        ],
      ];

      final puller = SyncPuller(db: db, fetch: fake.call);
      final pulled = await puller.pullTable(const SyncTable(
        name: 'valid_transitions',
        watermarkColumn: 'created_at',
      ));

      expect(pulled, 2);
      final rows = await (db.select(db.validTransitions)
            ..orderBy([(t) => OrderingTerm(expression: t.id)]))
          .get();
      expect(rows.map((r) => r.id).toList(), ['vt-1', 'vt-2']);
      expect(rows[0].fromStatus, isNull);
      expect(rows[0].toStatus, 'received');
      expect(rows[1].fromStatus, 'ready');
      expect(rows[1].toStatus, 'out_for_delivery');
    });
  });
}
