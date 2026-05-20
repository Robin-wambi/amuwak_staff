import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_staff/src/data/app_database.dart';
import 'package:amuwak_staff/src/sync/staff_repository.dart';

Future<void> _insertStaff(
  AppDatabase db, {
  required String id,
  required String username,
  required String displayName,
  String role = 'driver',
  DateTime? deletedAt,
}) async {
  final now = DateTime.utc(2026, 5, 19, 10, 0);
  await db.into(db.staff).insert(StaffCompanion.insert(
        id: id,
        username: username,
        displayName: displayName,
        role: role,
        createdAt: now,
        updatedAt: now,
        deletedAt: Value(deletedAt),
      ));
}

void main() {
  late AppDatabase db;
  late StaffRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = StaffRepository(db);
  });

  tearDown(() async => db.close());

  group('StaffRepository.watchAll', () {
    test('emits an empty list when the staff table is empty', () async {
      final list = await repo.watchAll().first;
      expect(list, isEmpty);
    });

    test('orders rows alphabetically by displayName', () async {
      await _insertStaff(db, id: 's-1', username: 'brian', displayName: 'Brian K.');
      await _insertStaff(db, id: 's-2', username: 'alice', displayName: 'Alice N.');
      await _insertStaff(db, id: 's-3', username: 'carol', displayName: 'Carol M.');

      final list = await repo.watchAll().first;
      expect(list.map((s) => s.displayName).toList(),
          ['Alice N.', 'Brian K.', 'Carol M.']);
    });

    test('excludes soft-deleted rows', () async {
      await _insertStaff(db, id: 's-1', username: 'alice', displayName: 'Alice');
      await _insertStaff(
        db,
        id: 's-2',
        username: 'bob',
        displayName: 'Bob',
        deletedAt: DateTime.utc(2026, 5, 19, 12, 0),
      );

      final list = await repo.watchAll().first;
      expect(list.map((s) => s.id).toList(), ['s-1']);
    });
  });

  group('StaffRepository.watchById', () {
    test('emits null for an unknown id', () async {
      final value = await repo.watchById('does-not-exist').first;
      expect(value, isNull);
    });

    test('emits the row for a known id', () async {
      await _insertStaff(db, id: 's-1', username: 'alice', displayName: 'Alice');

      final value = await repo.watchById('s-1').first;
      expect(value, isNotNull);
      expect(value!.id, 's-1');
      expect(value.username, 'alice');
      expect(value.displayName, 'Alice');
    });
  });
}
