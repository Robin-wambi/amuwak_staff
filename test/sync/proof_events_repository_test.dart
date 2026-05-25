import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_staff/src/data/app_database.dart';
import 'package:amuwak_staff/src/sync/proof_events_repository.dart';

Future<void> _insertProofEvent(
  AppDatabase db, {
  required String id,
  required String orderId,
  required String type,
  required DateTime capturedAt,
  String? notes,
  DateTime? deletedAt,
}) async {
  await db.into(db.proofEvents).insert(ProofEventsCompanion.insert(
        id: id,
        orderId: orderId,
        type: type,
        capturedAt: capturedAt,
        itemCount: 5,
        notes: Value(notes),
        capturedBy: 's-1',
        createdAt: capturedAt,
        updatedAt: capturedAt,
        deletedAt: Value(deletedAt),
      ));
}

void main() {
  late AppDatabase db;
  late ProofEventsRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = ProofEventsRepository(db);
  });

  tearDown(() async => db.close());

  group('ProofEventsRepository.watchByOrder', () {
    test('emits an empty list when there are no events for the order', () async {
      final list = await repo.watchByOrder('AMW-A').first;
      expect(list, isEmpty);
    });

    test('returns only events for the requested order, ordered by capturedAt', () async {
      await _insertProofEvent(
        db,
        id: 'pe-1',
        orderId: 'AMW-A',
        type: 'pickup',
        capturedAt: DateTime.utc(2026, 5, 19, 10, 30),
      );
      await _insertProofEvent(
        db,
        id: 'pe-2',
        orderId: 'AMW-A',
        type: 'delivery',
        capturedAt: DateTime.utc(2026, 5, 19, 16, 0),
      );
      await _insertProofEvent(
        db,
        id: 'pe-other',
        orderId: 'AMW-B',
        type: 'pickup',
        capturedAt: DateTime.utc(2026, 5, 19, 11, 0),
      );

      final list = await repo.watchByOrder('AMW-A').first;
      expect(list.map((e) => e.id).toList(), ['pe-1', 'pe-2']);
      expect(list.every((e) => e.orderId == 'AMW-A'), isTrue);
    });

    test('orders events by capturedAt even when inserted out of order', () async {
      await _insertProofEvent(
        db,
        id: 'pe-late',
        orderId: 'AMW-A',
        type: 'delivery',
        capturedAt: DateTime.utc(2026, 5, 19, 16, 0),
      );
      await _insertProofEvent(
        db,
        id: 'pe-early',
        orderId: 'AMW-A',
        type: 'pickup',
        capturedAt: DateTime.utc(2026, 5, 19, 10, 30),
      );

      final list = await repo.watchByOrder('AMW-A').first;
      expect(list.map((e) => e.id).toList(), ['pe-early', 'pe-late']);
    });

    test('excludes soft-deleted events', () async {
      await _insertProofEvent(
        db,
        id: 'pe-1',
        orderId: 'AMW-A',
        type: 'pickup',
        capturedAt: DateTime.utc(2026, 5, 19, 10, 30),
      );
      await _insertProofEvent(
        db,
        id: 'pe-deleted',
        orderId: 'AMW-A',
        type: 'delivery',
        capturedAt: DateTime.utc(2026, 5, 19, 16, 0),
        deletedAt: DateTime.utc(2026, 5, 19, 17, 0),
      );

      final list = await repo.watchByOrder('AMW-A').first;
      expect(list.map((e) => e.id).toList(), ['pe-1']);
    });
  });
}
