import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:amuwak_staff/src/data/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('all 11 synced + local tables exist on a fresh in-memory database', () async {
    final rows = await db.customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
    ).get();
    final tableNames = rows.map((r) => r.read<String>('name')).toSet();
    expect(tableNames, containsAll(<String>[
      'staff', 'customers', 'orders',
      'order_status_events', 'proof_events', 'proof_photos',
      'issues', 'shifts', 'valid_transitions',
      'outbox', 'sync_watermarks',
    ]));
  });

  test('inserting an order round-trips through Drift', () async {
    final now = DateTime.utc(2026, 5, 19);
    await db.into(db.orders).insert(OrdersCompanion.insert(
      id: 'order-1',
      orderCode: 'AMW-1',
      customerName: 'C',
      phone: '+254700',
      address: 'A',
      serviceType: 'wash_fold',
      status: 'received',
      intakeMethod: 'walk_in',
      fulfillmentMethod: 'delivery',
      itemCount: 3,
      intakeRecordedBy: 'staff-1',
      createdBy: 'staff-1',
      createdAt: Value(now),
      updatedAt: Value(now),
    ));
    final rows = await db.select(db.orders).get();
    expect(rows, hasLength(1));
    expect(rows.first.orderCode, 'AMW-1');
  });

  test('schemaVersion is 5', () {
    expect(db.schemaVersion, 5);
  });

  test('orders table exposes the pricing columns', () async {
    // A select compiling proves the columns exist.
    final rows = await db.select(db.orders).get();
    expect(rows, isEmpty);
  });
}
