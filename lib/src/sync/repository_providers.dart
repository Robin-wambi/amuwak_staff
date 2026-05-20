import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'customers_repository.dart';
import 'orders_repository.dart';
import 'proof_events_repository.dart';
import 'staff_repository.dart';
import 'status_events_repository.dart';
import 'sync_status.dart';

/// Riverpod providers for the read-side repositories built in Plan 3a
/// Tasks 2–4. Each provider depends on [appDatabaseProvider] so test
/// suites can override the database with an in-memory instance and the
/// repos pick it up automatically.

final ordersRepositoryProvider = Provider<OrdersRepository>(
  (ref) => OrdersRepository(ref.watch(appDatabaseProvider)),
);

final customersRepositoryProvider = Provider<CustomersRepository>(
  (ref) => CustomersRepository(ref.watch(appDatabaseProvider)),
);

final staffRepositoryProvider = Provider<StaffRepository>(
  (ref) => StaffRepository(ref.watch(appDatabaseProvider)),
);

final proofEventsRepositoryProvider = Provider<ProofEventsRepository>(
  (ref) => ProofEventsRepository(ref.watch(appDatabaseProvider)),
);

final statusEventsRepositoryProvider = Provider<StatusEventsRepository>(
  (ref) => StatusEventsRepository(ref.watch(appDatabaseProvider)),
);
