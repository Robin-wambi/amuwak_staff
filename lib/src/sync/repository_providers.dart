import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'customers_repository.dart';
import 'orders_repository.dart';
import 'outbox_repository.dart';
import 'proof_events_repository.dart';
import 'staff_repository.dart';
import 'status_events_repository.dart';
import 'sync_status.dart';

/// Riverpod providers for the sync-layer repositories (read and write).
/// Read-side repos (Plan 3a Tasks 2–4): [ordersRepositoryProvider],
/// [customersRepositoryProvider], [staffRepositoryProvider],
/// [proofEventsRepositoryProvider], [statusEventsRepositoryProvider].
/// Write-side infra (Plan 3b Task 3+): [outboxRepositoryProvider].
/// Each provider depends on [appDatabaseProvider] so test suites can
/// override the database with an in-memory instance.

final ordersRepositoryProvider = Provider<OrdersRepository>(
  (ref) => OrdersRepository(
    ref.watch(appDatabaseProvider),
    outbox: ref.watch(outboxRepositoryProvider),
  ),
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

final outboxRepositoryProvider = Provider<OutboxRepository>(
  (ref) => OutboxRepository(ref.watch(appDatabaseProvider)),
);
