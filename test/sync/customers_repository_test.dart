import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_staff/src/data/app_database.dart';
import 'package:amuwak_staff/src/sync/customers_repository.dart';

Future<void> _insertCustomer(
  AppDatabase db, {
  required String id,
  required String name,
  String phone = '+256 700 000 000',
  DateTime? deletedAt,
}) async {
  final now = DateTime.utc(2026, 5, 19, 10, 0);
  await db.into(db.customers).insert(CustomersCompanion.insert(
        id: id,
        name: name,
        phone: phone,
        createdAt: now,
        updatedAt: now,
        deletedAt: Value(deletedAt),
      ));
}

void main() {
  late AppDatabase db;
  late CustomersRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = CustomersRepository(db);
  });

  tearDown(() async => db.close());

  group('CustomersRepository.watchAll', () {
    test('emits an empty list when the customers table is empty', () async {
      final list = await repo.watchAll().first;
      expect(list, isEmpty);
    });

    test('orders rows alphabetically by name', () async {
      await _insertCustomer(db, id: 'c-1', name: 'Brian K.');
      await _insertCustomer(db, id: 'c-2', name: 'Alice N.');
      await _insertCustomer(db, id: 'c-3', name: 'Carol M.');

      final list = await repo.watchAll().first;
      expect(list.map((c) => c.name).toList(),
          ['Alice N.', 'Brian K.', 'Carol M.']);
    });

    test('excludes soft-deleted rows', () async {
      await _insertCustomer(db, id: 'c-1', name: 'Alice');
      await _insertCustomer(
        db,
        id: 'c-2',
        name: 'Bob',
        deletedAt: DateTime.utc(2026, 5, 19, 12, 0),
      );

      final list = await repo.watchAll().first;
      expect(list.map((c) => c.id).toList(), ['c-1']);
    });
  });

  group('CustomersRepository.watchById', () {
    test('emits null for an unknown id', () async {
      final value = await repo.watchById('does-not-exist').first;
      expect(value, isNull);
    });

    test('emits the row for a known id', () async {
      await _insertCustomer(db, id: 'c-1', name: 'Alice');

      final value = await repo.watchById('c-1').first;
      expect(value, isNotNull);
      expect(value!.id, 'c-1');
      expect(value.name, 'Alice');
    });
  });
}
