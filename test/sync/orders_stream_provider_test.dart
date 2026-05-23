import 'dart:async';

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
    // Listen for the post-write emission via container.listen — completes a
    // Completer the moment AsyncData lands with at least one row. Avoids
    // the previous `Future.delayed(30ms)` polling, which was flaky on slow CI.
    final firstNonEmpty = Completer<List<LaundryOrder>>();
    final sub = container.listen<AsyncValue<List<LaundryOrder>>>(
      ordersStreamProvider,
      (prev, next) {
        final value = next.valueOrNull;
        if (value != null && value.isNotEmpty && !firstNonEmpty.isCompleted) {
          firstNonEmpty.complete(value);
        }
      },
      fireImmediately: true,
    );
    addTearDown(sub.close);

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

    final latest =
        await firstNonEmpty.future.timeout(const Duration(seconds: 2));
    expect(latest, hasLength(1));
    expect(latest.single.orderId, 'AMW-A');
  });
}
