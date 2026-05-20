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
}
