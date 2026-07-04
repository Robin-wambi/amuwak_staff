import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../expenses/expense.dart';
import '../expenses/expenses_repository.dart';
import '../orders/order.dart';
import '../staff/invite_staff_service.dart';
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
///
/// OPS DEPENDENCY — Realtime publication: the read repos use Supabase
/// `.stream(...)`, which only pushes *live* changes for tables in the
/// `supabase_realtime` publication. Without it, lists load the initial
/// snapshot but never update after a write in the same session (and the
/// new-pickup → capture auto-advance won't fire). Every environment must run:
///
///   alter publication supabase_realtime add table
///     public.orders, public.customers, public.proof_events,
///     public.staff, public.order_status_events, public.expenses;
///
/// See docs/online-only-mode.md for the full ops checklist.
final supabaseClientProvider =
    Provider<SupabaseClient>((_) => Supabase.instance.client);

final ordersRepositoryProvider = Provider<OrdersRepository>(
  (ref) => OrdersRepository(
    ref.watch(appDatabaseProvider),
    outbox: ref.watch(outboxRepositoryProvider),
  ),
);

final customersRepositoryProvider = Provider<CustomersRepository>(
  (ref) => CustomersRepository(ref.watch(supabaseClientProvider)),
);

final staffRepositoryProvider = Provider<StaffRepository>(
  (ref) => StaffRepository(ref.watch(supabaseClientProvider)),
);

final proofEventsRepositoryProvider = Provider<ProofEventsRepository>(
  (ref) => ProofEventsRepository(
    ref.watch(appDatabaseProvider),
    outbox: ref.watch(outboxRepositoryProvider),
  ),
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

final expensesRepositoryProvider = Provider<ExpensesRepository>(
  (ref) => ExpensesRepository(ref.watch(supabaseClientProvider)),
);

final expensesStreamProvider = StreamProvider<List<Expense>>(
  (ref) => ref.watch(expensesRepositoryProvider).watchAll(),
);

final inviteStaffServiceProvider = Provider<InviteStaffService>(
  (ref) => InviteStaffService(ref.watch(supabaseClientProvider)),
);
