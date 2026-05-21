import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_staff/src/data/app_database.dart';
import 'package:amuwak_staff/src/orders/order.dart';
import 'package:amuwak_staff/src/orders/order_status.dart';
import 'package:amuwak_staff/src/sync/repository_providers.dart';
import 'package:amuwak_staff/src/sync/sync_status.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
    ]);
  });
  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('ordersStreamProvider emits orders inserted through OrdersRepository', () async {
    // Initial emission — empty.
    final firstFrame = await container.read(ordersStreamProvider.future);
    expect(firstFrame, isEmpty);

    // Insert through the repo write path.
    await container.read(ordersRepositoryProvider).upsertOrder(
      const LaundryOrder(
        orderId: 'AMW-A',
        customerName: 'Sarah',
        serviceType: 'wash',
        status: OrderStatus.pendingPickup,
        timeLabel: '10:00 AM',
        itemCount: 3,
        phone: '+256',
        address: 'addr',
        notes: '',
      ),
      actorStaffId: 's-1',
    );

    // Allow Drift's stream notification to propagate.
    await Future<void>.delayed(const Duration(milliseconds: 30));
    final next = container.read(ordersStreamProvider).valueOrNull;
    expect(next, isNotNull);
    expect(next!.single.orderId, 'AMW-A');
  });
}
