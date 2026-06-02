import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../orders/order.dart';
import 'customers_repository.dart';
import 'orders_repository.dart';
import 'outbox_repository.dart';
import 'proof_events_repository.dart';
import 'pull_dead_letter_repository.dart';
import 'staff_repository.dart';
import 'status_events_repository.dart';
import 'sync_status.dart';

/// Riverpod providers for the repositories.
///
/// ONLINE-ONLY mode: the read/write repos talk directly to Supabase via
/// [supabaseClientProvider]. The offline write infrastructure
/// ([outboxRepositoryProvider], [pullDeadLetterRepositoryProvider]) is kept
/// defined but is no longer watched by the live app — the SyncOrchestrator is
/// disabled, the banner removed, and the SyncErrorsScreen unreachable, so the
/// local Drift database (lazily opened on first query) is never opened.
/// Re-point the five repo providers back at [appDatabaseProvider] +
/// [outboxRepositoryProvider] to restore offline mode.

/// Singleton Supabase client. Tests override this with a mock/fake client.
final supabaseClientProvider =
    Provider<SupabaseClient>((_) => Supabase.instance.client);

final ordersRepositoryProvider = Provider<OrdersRepository>(
  (ref) => OrdersRepository(ref.watch(supabaseClientProvider)),
);

final customersRepositoryProvider = Provider<CustomersRepository>(
  (ref) => CustomersRepository(ref.watch(supabaseClientProvider)),
);

final staffRepositoryProvider = Provider<StaffRepository>(
  (ref) => StaffRepository(ref.watch(supabaseClientProvider)),
);

final proofEventsRepositoryProvider = Provider<ProofEventsRepository>(
  (ref) => ProofEventsRepository(ref.watch(supabaseClientProvider)),
);

final statusEventsRepositoryProvider = Provider<StatusEventsRepository>(
  (ref) => StatusEventsRepository(ref.watch(supabaseClientProvider)),
);

// OFFLINE write infra — preserved, unused in online-only mode. Still depends on
// [appDatabaseProvider]; only ever constructed if something watches them
// (nothing in the live app does), so the local DB stays closed.
final outboxRepositoryProvider = Provider<OutboxRepository>(
  (ref) => OutboxRepository(ref.watch(appDatabaseProvider)),
);

final pullDeadLetterRepositoryProvider =
    Provider<PullDeadLetterRepository>(
  (ref) => PullDeadLetterRepository(ref.watch(appDatabaseProvider)),
);

final ordersStreamProvider = StreamProvider<List<LaundryOrder>>(
  (ref) => ref.watch(ordersRepositoryProvider).watchAll(),
);
