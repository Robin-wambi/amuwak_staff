import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_staff/src/data/app_database.dart';
import 'package:amuwak_staff/src/sync/status_events_repository.dart';

Future<void> _insertStatusEvent(
  AppDatabase db, {
  required String id,
  required String orderId,
  String? fromStatus,
  required String toStatus,
  required DateTime changedAt,
  String source = 'mobile',
}) async {
  await db.into(db.orderStatusEvents).insert(OrderStatusEventsCompanion.insert(
        id: id,
        orderId: orderId,
        fromStatus: Value(fromStatus),
        toStatus: toStatus,
        changedBy: 's-1',
        changedAt: changedAt,
        source: source,
      ));
}

void main() {
  late AppDatabase db;
  late StatusEventsRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = StatusEventsRepository(db);
  });

  tearDown(() async => db.close());

  group('StatusEventsRepository.watchByOrder', () {
    test('emits an empty list when there are no events for the order', () async {
      final list = await repo.watchByOrder('AMW-A').first;
      expect(list, isEmpty);
    });

    test('returns only events for the requested order, ordered by changedAt', () async {
      await _insertStatusEvent(
        db,
        id: 'se-1',
        orderId: 'AMW-A',
        fromStatus: null,
        toStatus: 'pending_pickup',
        changedAt: DateTime.utc(2026, 5, 19, 9, 0),
      );
      await _insertStatusEvent(
        db,
        id: 'se-2',
        orderId: 'AMW-A',
        fromStatus: 'pending_pickup',
        toStatus: 'received',
        changedAt: DateTime.utc(2026, 5, 19, 10, 30),
      );
      await _insertStatusEvent(
        db,
        id: 'se-other',
        orderId: 'AMW-B',
        fromStatus: null,
        toStatus: 'pending_pickup',
        changedAt: DateTime.utc(2026, 5, 19, 11, 0),
      );

      final list = await repo.watchByOrder('AMW-A').first;
      expect(list.map((e) => e.id).toList(), ['se-1', 'se-2']);
      expect(list.every((e) => e.orderId == 'AMW-A'), isTrue);
    });

    test('orders events chronologically even when inserted out of order', () async {
      await _insertStatusEvent(
        db,
        id: 'se-late',
        orderId: 'AMW-A',
        fromStatus: 'in_progress',
        toStatus: 'ready',
        changedAt: DateTime.utc(2026, 5, 19, 14, 0),
      );
      await _insertStatusEvent(
        db,
        id: 'se-early',
        orderId: 'AMW-A',
        fromStatus: null,
        toStatus: 'pending_pickup',
        changedAt: DateTime.utc(2026, 5, 19, 9, 0),
      );

      final list = await repo.watchByOrder('AMW-A').first;
      expect(list.map((e) => e.id).toList(), ['se-early', 'se-late']);
    });
  });

  group('StatusEventsRepository append-only contract', () {
    test('exposes no mutating methods (update / delete / append)', () {
      // Reflection isn't worth pulling in for a one-line guard; rely on
      // the static type system instead. The dynamic invocation below
      // documents the contract: these names should not resolve.
      final dynamic d = repo;
      expect(() => d.update('any'), throwsNoSuchMethodError);
      expect(() => d.delete('any'), throwsNoSuchMethodError);
      expect(() => d.append('any'), throwsNoSuchMethodError);
    });
  });
}
