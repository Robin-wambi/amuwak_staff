import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:amuwak_staff/src/auth/login_screen.dart';
import 'package:amuwak_staff/src/auth/session.dart';
import 'package:amuwak_staff/src/dashboard/current_staff_provider.dart';
import 'package:amuwak_staff/src/dashboard/staff_dashboard_screen.dart';
import 'package:amuwak_staff/src/shared/motion/animated_gradient_header.dart';
import 'package:amuwak_staff/src/expenses/expense.dart';
import 'package:amuwak_staff/src/expenses/expense_entry_screen.dart';
import 'package:amuwak_staff/src/notifications/notifications_screen.dart';
import 'package:amuwak_staff/src/orders/new_pickup_screen.dart';
import 'package:amuwak_staff/src/orders/edit_order_screen.dart';
import 'package:amuwak_staff/src/orders/order.dart';
import 'package:amuwak_staff/src/orders/order_details_screen.dart';
import 'package:amuwak_staff/src/orders/order_filter_screen.dart';
import 'package:amuwak_staff/src/orders/order_search_screen.dart';
import 'package:amuwak_staff/src/orders/order_status.dart';
import 'package:amuwak_staff/src/orders/proof_event.dart';
import 'package:amuwak_staff/src/orders/service_type.dart';
import 'package:amuwak_staff/src/reports/daily_report_screen.dart';
import 'package:amuwak_staff/src/reports/items_breakdown_screen.dart';
import 'package:amuwak_staff/src/orders/widgets/order_card.dart';
import 'package:amuwak_staff/src/data/app_database.dart' hide ProofEvent;
import 'package:amuwak_staff/src/shared/widgets/sync_status_banner.dart';
import 'package:amuwak_staff/src/pricing/pricing_providers.dart';
import 'package:amuwak_staff/src/pricing/pricing_settings.dart';
import 'package:amuwak_staff/src/pricing/pricing_settings_repository.dart';
import 'package:amuwak_staff/src/sync/customers_repository.dart';
import 'package:amuwak_staff/src/sync/orders_repository.dart';
import 'package:amuwak_staff/src/sync/repository_providers.dart';
import 'package:amuwak_staff/src/sync/sync_errors_provider.dart';
import 'package:amuwak_staff/src/sync/sync_errors_screen.dart';
import 'package:amuwak_staff/src/sync/sync_status.dart';

/// Pumps StaffDashboardScreen inside a ProviderScope with stubbed sync
/// providers, so callers can decide what (if anything) to seed via
/// [extraOverrides].
///
/// Drift stream providers ([pendingOutboxCountProvider],
/// [lastSyncedAtProvider], [ordersStreamProvider]) are overridden with
/// simple Dart streams so that no Drift `QueryStream` subscriptions are
/// open at test teardown — this avoids the zero-duration debounce timer
/// that `StreamQueryStore.markAsClosed` posts when a Drift stream is
/// cancelled, which would fail the Flutter test framework's
/// `!timersPending` invariant.
/// Online-only mode: the read/write repos resolve the Supabase client via
/// [supabaseClientProvider]. Tests never initialise `Supabase.instance`, so
/// override it with a mock — the repo constructors only store the client (no
/// calls), which is enough for navigation tests like "open New pickup".
class _MockSupabaseClient extends Mock implements SupabaseClient {}

/// Stub repos so opening NewPickupScreen — whose initState reads orders +
/// customers to seed the address auto-suggest — doesn't hit the unstubbed
/// Supabase mock. Both reads resolve to empty lists, which is all the
/// navigation tests need.
class _StubOrdersRepository extends Mock implements OrdersRepository {}

class _StubCustomersRepository extends Mock implements CustomersRepository {}

/// Stub repository that always returns a settings row with [defaultRatePerKgUgx]
/// so dashboard tests can open NewPickupScreen without hitting Supabase.
class _FakePricingSettingsRepository extends PricingSettingsRepository {
  _FakePricingSettingsRepository({double defaultRatePerKgUgx = 5000})
      : _settings = PricingSettings(
          id: 'settings-1',
          defaultRatePerKgUgx: defaultRatePerKgUgx,
          updatedAt: DateTime(2026, 5, 25),
        ),
        super.forTest(fetchRows: () async => []);

  final PricingSettings _settings;

  @override
  Future<PricingSettings> fetch() async => _settings;
}

Future<void> pumpDashboardWithDb(
  WidgetTester tester, {
  bool lostPhoto = false,
  List<Override> extraOverrides = const [],
}) async {
  final stubOrdersRepo = _StubOrdersRepository();
  final stubCustomersRepo = _StubCustomersRepository();
  when(() => stubOrdersRepo.getAll()).thenAnswer((_) async => <LaundryOrder>[]);
  when(() => stubCustomersRepo.getAll())
      .thenAnswer((_) async => <Customer>[]);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        supabaseClientProvider.overrideWithValue(_MockSupabaseClient()),
        // Empty read-repos so NewPickupScreen's address-suggest init resolves
        // without touching the unstubbed Supabase mock.
        ordersRepositoryProvider.overrideWithValue(stubOrdersRepo),
        customersRepositoryProvider.overrideWithValue(stubCustomersRepo),
        // Provide a trivial in-memory implementation of every Drift-backed
        // stream so that no real Drift stream subscriptions are opened.
        pendingOutboxCountProvider
            .overrideWith((ref) => const Stream<int>.empty()),
        lastSyncedAtProvider
            .overrideWith((ref) => const Stream<DateTime?>.empty()),
        ordersStreamProvider
            .overrideWith((ref) => Stream<List<LaundryOrder>>.value(const [])),
        // The report tab watches expenses; keep it off the Supabase mock.
        expensesStreamProvider
            .overrideWith((ref) => Stream<List<Expense>>.value(const [])),
        outboxDeadLetteredProvider.overrideWith(
            (ref) => Stream<List<OutboxData>>.value(const [])),
        pullDeadLetteredProvider.overrideWith(
            (ref) => Stream<List<PullDeadLetterData>>.value(const [])),
        // Provide a stub repo so _handleNewPickup can fetch the rate and open
        // NewPickupScreen without hitting the real Supabase client.
        pricingSettingsRepositoryProvider
            .overrideWithValue(_FakePricingSettingsRepository()),
        // The header greets the signed-in staff member; keep it off the
        // Supabase mock and deterministic (no name) in tests.
        currentStaffProvider
            .overrideWith((ref) => Stream<StaffData?>.value(null)),
        ...extraOverrides,
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child:
                StaffDashboardScreen(retrieveLostPhoto: () async => lostPhoto),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// A fallback so mocktail's `any()` matcher works for the LaundryOrder argument
/// of `updateOrderDetails` in the CRUD-wiring tests below.
const _fallbackOrder = LaundryOrder(
  orderId: 'fallback',
  customerName: 'fallback',
  serviceType: ServiceType.washOnly,
  status: OrderStatus.inProgress,
  timeLabel: 't',
  itemCount: 1,
  phone: 'p',
  address: 'a',
  notes: '',
);

void main() {
  setUpAll(() {
    registerFallbackValue(_fallbackOrder);
    // updateStatus takes a non-nullable OrderStatus positionally; mocktail's
    // any() matcher needs a fallback value for it.
    registerFallbackValue(OrderStatus.inProgress);
  });

  testWidgets(
    'Surfaces a SnackBar on startup when an in-flight photo capture was lost',
    (tester) async {
      await pumpDashboardWithDb(tester, lostPhoto: true);

      expect(
        find.textContaining('photo capture was interrupted'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Does not show the lost-capture SnackBar when nothing was lost',
    (tester) async {
      await pumpDashboardWithDb(tester);

      expect(
        find.textContaining('photo capture was interrupted'),
        findsNothing,
      );
    },
  );

  testWidgets('Bottom navigation switches between staff sections', (
    tester,
  ) async {
    await pumpDashboardWithDb(tester);

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('Amuwak Staff'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Report').last);
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('Daily report'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Account').last);
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('Account'),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'Tapping the bell opens NotificationsScreen',
    (tester) async {
      await pumpDashboardWithDb(tester);

      await tester.tap(find.byTooltip('Notifications'));
      await tester.pumpAndSettle();

      expect(find.byType(NotificationsScreen), findsOneWidget);
    },
  );

  testWidgets(
    'Tapping "New pickup" opens NewPickupScreen',
    (tester) async {
      await pumpDashboardWithDb(tester, extraOverrides: [
        currentUserIdProvider.overrideWith((ref) => 'staff-1'),
      ]);

      await tester.ensureVisible(find.text('New pickup', skipOffstage: false));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New pickup'));
      await tester.pumpAndSettle();

      expect(find.byType(NewPickupScreen), findsOneWidget);
    },
  );

  testWidgets(
    'Tapping "New pickup" with a null staffId shows a session-expired '
    'SnackBar instead of pushing NewPickupScreen',
    (tester) async {
      await pumpDashboardWithDb(tester, extraOverrides: [
        currentUserIdProvider.overrideWith((ref) => null),
      ]);

      await tester.ensureVisible(find.text('New pickup', skipOffstage: false));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New pickup'));
      await tester.pumpAndSettle();

      expect(find.byType(NewPickupScreen), findsNothing);
      expect(find.text('Session expired — please sign in again.'),
          findsOneWidget);
    },
  );

  testWidgets(
    'Orders tab shows a "New pickup" FAB that opens NewPickupScreen',
    (tester) async {
      await pumpDashboardWithDb(tester, extraOverrides: [
        currentUserIdProvider.overrideWith((ref) => 'staff-1'),
      ]);

      await tester.tap(find.text('Orders').last);
      await tester.pumpAndSettle();

      final fab = find.widgetWithText(FloatingActionButton, 'New pickup');
      expect(fab, findsOneWidget);
      await tester.tap(fab);
      await tester.pumpAndSettle();

      expect(find.byType(NewPickupScreen), findsOneWidget);
    },
  );

  group('Orders tab card CRUD wiring', () {
    LaundryOrder inProgress(String name) => LaundryOrder(
          orderId: 'o-$name',
          orderCode: 'AMW-$name',
          customerName: name,
          serviceType: ServiceType.washAndIron,
          status: OrderStatus.inProgress,
          timeLabel: 't',
          itemCount: 3,
          phone: '0700',
          address: 'Kira',
          notes: '',
        );

    testWidgets(
      'long-press → Edit details → save calls updateOrderDetails with the '
      'edited order',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final repo = _StubOrdersRepository();
        when(() => repo.getAll())
            .thenAnswer((_) async => <LaundryOrder>[]);
        when(() => repo.updateOrderDetails(any(),
            actorStaffId: any(named: 'actorStaffId'))).thenAnswer((_) async {});

        await pumpDashboardWithDb(tester, extraOverrides: [
          ordersStreamProvider.overrideWith(
            (ref) => Stream<List<LaundryOrder>>.value([inProgress('Zara')]),
          ),
          ordersRepositoryProvider.overrideWithValue(repo),
          currentUserIdProvider.overrideWith((ref) => 'staff-1'),
        ]);

        await tester.tap(find.text('Orders').last);
        await tester.pumpAndSettle();

        await tester.longPress(find.text('Zara'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Edit details'));
        await tester.pumpAndSettle();
        expect(find.byType(EditOrderScreen), findsOneWidget);

        await tester.enterText(
            find.byKey(const Key('edit_customer_name')), 'Zara Edited');
        await tester.ensureVisible(find.byKey(const Key('edit_save')));
        await tester.tap(find.byKey(const Key('edit_save')));
        await tester.pumpAndSettle();

        final captured = verify(() => repo.updateOrderDetails(
            captureAny(), actorStaffId: 'staff-1')).captured.single;
        expect((captured as LaundryOrder).customerName, 'Zara Edited');
        expect(captured.orderId, 'o-Zara');
      },
    );

    testWidgets(
      'swipe-to-delete → confirm calls softDelete with the order id',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final repo = _StubOrdersRepository();
        when(() => repo.getAll())
            .thenAnswer((_) async => <LaundryOrder>[]);
        when(() => repo.softDelete(any(),
            actorStaffId: any(named: 'actorStaffId'))).thenAnswer((_) async {});

        await pumpDashboardWithDb(tester, extraOverrides: [
          ordersStreamProvider.overrideWith(
            (ref) => Stream<List<LaundryOrder>>.value([inProgress('Zeta')]),
          ),
          ordersRepositoryProvider.overrideWithValue(repo),
          currentUserIdProvider.overrideWith((ref) => 'staff-1'),
        ]);

        await tester.tap(find.text('Orders').last);
        await tester.pumpAndSettle();

        await tester.drag(find.text('Zeta'), const Offset(-500, 0));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        await tester.tap(find.text('Delete'));
        await tester.pumpAndSettle();

        verify(() => repo.softDelete('o-Zeta', actorStaffId: 'staff-1'))
            .called(1);
      },
    );

    testWidgets(
      'long-press → Mark as Ready for delivery calls updateStatus to the '
      'proof-less next step',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final repo = _StubOrdersRepository();
        when(() => repo.getAll()).thenAnswer((_) async => <LaundryOrder>[]);
        when(() => repo.updateStatus(any(), any(),
            actorStaffId: any(named: 'actorStaffId'))).thenAnswer((_) async {});

        await pumpDashboardWithDb(tester, extraOverrides: [
          ordersStreamProvider.overrideWith(
            (ref) => Stream<List<LaundryOrder>>.value([inProgress('Zane')]),
          ),
          ordersRepositoryProvider.overrideWithValue(repo),
          currentUserIdProvider.overrideWith((ref) => 'staff-1'),
        ]);

        await tester.tap(find.text('Orders').last);
        await tester.pumpAndSettle();

        await tester.longPress(find.text('Zane'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Mark as Ready for delivery'));
        await tester.pumpAndSettle();

        verify(() => repo.updateStatus(
              'o-Zane',
              OrderStatus.readyForDelivery,
              actorStaffId: 'staff-1',
            )).called(1);
      },
    );

    testWidgets(
      'Edit with no session shows session-expired, never opens EditOrderScreen',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await pumpDashboardWithDb(tester, extraOverrides: [
          ordersStreamProvider.overrideWith(
            (ref) => Stream<List<LaundryOrder>>.value([inProgress('Nyx')]),
          ),
          currentUserIdProvider.overrideWith((ref) => null),
        ]);

        await tester.tap(find.text('Orders').last);
        await tester.pumpAndSettle();
        await tester.longPress(find.text('Nyx'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Edit details'));
        await tester.pumpAndSettle();

        expect(find.byType(EditOrderScreen), findsNothing);
        expect(find.text('Session expired — please sign in again.'),
            findsOneWidget);
      },
    );

    testWidgets(
      'a failing softDelete surfaces a retry SnackBar',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final repo = _StubOrdersRepository();
        when(() => repo.getAll()).thenAnswer((_) async => <LaundryOrder>[]);
        when(() => repo.softDelete(any(),
                actorStaffId: any(named: 'actorStaffId')))
            .thenThrow(Exception('boom'));

        await pumpDashboardWithDb(tester, extraOverrides: [
          ordersStreamProvider.overrideWith(
            (ref) => Stream<List<LaundryOrder>>.value([inProgress('Nix')]),
          ),
          ordersRepositoryProvider.overrideWithValue(repo),
          currentUserIdProvider.overrideWith((ref) => 'staff-1'),
        ]);

        await tester.tap(find.text('Orders').last);
        await tester.pumpAndSettle();
        await tester.drag(find.text('Nix'), const Offset(-500, 0));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete'));
        await tester.pumpAndSettle();

        expect(
            find.text('Could not delete — please retry.'), findsOneWidget);
      },
    );

    testWidgets(
      'a failing updateStatus surfaces a retry SnackBar',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final repo = _StubOrdersRepository();
        when(() => repo.getAll()).thenAnswer((_) async => <LaundryOrder>[]);
        when(() => repo.updateStatus(any(), any(),
                actorStaffId: any(named: 'actorStaffId')))
            .thenThrow(Exception('boom'));

        await pumpDashboardWithDb(tester, extraOverrides: [
          ordersStreamProvider.overrideWith(
            (ref) => Stream<List<LaundryOrder>>.value([inProgress('Nox')]),
          ),
          ordersRepositoryProvider.overrideWithValue(repo),
          currentUserIdProvider.overrideWith((ref) => 'staff-1'),
        ]);

        await tester.tap(find.text('Orders').last);
        await tester.pumpAndSettle();
        await tester.longPress(find.text('Nox'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Mark as Ready for delivery'));
        await tester.pumpAndSettle();

        expect(find.text('Could not update status — please retry.'),
            findsOneWidget);
      },
    );

    testWidgets(
      'Delete with no session shows session-expired and never calls softDelete',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final repo = _StubOrdersRepository();
        when(() => repo.getAll()).thenAnswer((_) async => <LaundryOrder>[]);

        await pumpDashboardWithDb(tester, extraOverrides: [
          ordersStreamProvider.overrideWith(
            (ref) => Stream<List<LaundryOrder>>.value([inProgress('Nul')]),
          ),
          ordersRepositoryProvider.overrideWithValue(repo),
          currentUserIdProvider.overrideWith((ref) => null),
        ]);

        await tester.tap(find.text('Orders').last);
        await tester.pumpAndSettle();
        await tester.drag(find.text('Nul'), const Offset(-500, 0));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete'));
        await tester.pumpAndSettle();

        expect(find.text('Session expired — please sign in again.'),
            findsOneWidget);
        verifyNever(() =>
            repo.softDelete(any(), actorStaffId: any(named: 'actorStaffId')));
      },
    );

    testWidgets(
      'Advance status with no session shows session-expired, no updateStatus',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final repo = _StubOrdersRepository();
        when(() => repo.getAll()).thenAnswer((_) async => <LaundryOrder>[]);

        await pumpDashboardWithDb(tester, extraOverrides: [
          ordersStreamProvider.overrideWith(
            (ref) => Stream<List<LaundryOrder>>.value([inProgress('Nil')]),
          ),
          ordersRepositoryProvider.overrideWithValue(repo),
          currentUserIdProvider.overrideWith((ref) => null),
        ]);

        await tester.tap(find.text('Orders').last);
        await tester.pumpAndSettle();
        await tester.longPress(find.text('Nil'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Mark as Ready for delivery'));
        await tester.pumpAndSettle();

        expect(find.text('Session expired — please sign in again.'),
            findsOneWidget);
        verifyNever(() => repo.updateStatus(any(), any(),
            actorStaffId: any(named: 'actorStaffId')));
      },
    );
  });

  testWidgets(
    'Tapping "Check order" opens OrderSearchScreen',
    (tester) async {
      await pumpDashboardWithDb(tester);

      await tester.ensureVisible(find.text('Check order', skipOffstage: false));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Check order'));
      await tester.pumpAndSettle();

      expect(find.byType(OrderSearchScreen), findsOneWidget);
    },
  );

  group('SyncStatusBanner mount (Plan 3a Task 14)', () {
    testWidgets('renders the offline banner when onlineProvider is false',
        (tester) async {
      await pumpDashboardWithDb(tester, extraOverrides: [
        onlineProvider.overrideWith((ref) => false),
      ]);

      expect(find.byType(SyncStatusBanner), findsOneWidget);
      expect(find.textContaining('Offline'), findsOneWidget);
    });

    testWidgets(
      'renders the pending-uploads banner with the count when online',
      (tester) async {
        await pumpDashboardWithDb(tester, extraOverrides: [
          onlineProvider.overrideWith((ref) => true),
          pendingOutboxCountProvider
              .overrideWith((ref) => Stream<int>.value(3)),
        ]);

        expect(find.byType(SyncStatusBanner), findsOneWidget);
        expect(find.textContaining('3 pending'), findsOneWidget);
      },
    );

    testWidgets(
      'hides the banner when online and the outbox is empty',
      (tester) async {
        await pumpDashboardWithDb(tester, extraOverrides: [
          onlineProvider.overrideWith((ref) => true),
          pendingOutboxCountProvider
              .overrideWith((ref) => Stream<int>.value(0)),
        ]);

        // Banner widget itself is still in the tree, but it renders
        // SizedBox.shrink — so no banner text is visible.
        expect(find.byType(SyncStatusBanner), findsOneWidget);
        expect(find.textContaining('Offline'), findsNothing);
        expect(find.textContaining('pending'), findsNothing);
      },
    );

    testWidgets('banner sits above the dashboard header', (tester) async {
      await pumpDashboardWithDb(tester, extraOverrides: [
        onlineProvider.overrideWith((ref) => false),
      ]);

      final bannerTop = tester.getTopLeft(find.byType(SyncStatusBanner));
      final headerTop = tester.getTopLeft(find.byType(AnimatedGradientHeader));
      expect(bannerTop.dy, lessThan(headerTop.dy));
    });
  },
      skip: 'Online-only mode: the SyncStatusBanner (offline/pending/error '
          'indicator) was removed from the dashboard. Restore the banner in '
          'StaffDashboardScreen to re-enable these tests.');

  // ------------------------------------------------------------------ Task 9

  testWidgets(
      'the Assigned card opens a filtered screen listing each row in '
      'ordersStreamProvider', (tester) async {
    // The order list now lives behind the summary cards rather than on Home.
    // Seed a single order, open it via the Assigned card, and verify its card
    // renders on the filtered screen.
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    const seeded = LaundryOrder(
      orderId: 'X',
      customerName: 'Test',
      serviceType: ServiceType.washOnly,
      status: OrderStatus.pendingPickup,
      timeLabel: '10:00 AM',
      itemCount: 1,
      phone: 'p',
      address: 'a',
      notes: '',
    );

    await pumpDashboardWithDb(tester, extraOverrides: [
      ordersStreamProvider.overrideWith(
        (ref) => Stream<List<LaundryOrder>>.value(const [seeded]),
      ),
    ]);

    await tester.tap(find.text('Assigned'));
    await tester.pumpAndSettle();

    expect(find.byType(OrderFilterScreen), findsOneWidget);
    expect(find.text('Test'), findsOneWidget);
  });

  testWidgets(
      'loading branch shows a progress indicator and no zero-count summary',
      (tester) async {
    // Override ordersStreamProvider with a stream that never emits — keeps
    // Riverpod's AsyncValue in the loading state.  SyncStatusBanner providers
    // and the dead-letter providers (read transitively via
    // syncErrorCountProvider) are also stubbed so no real Drift stream is
    // opened — drift_flutter's driftDatabase() schedules a Future at
    // connection time, which would leave a pending Timer at test teardown.
    await tester.pumpWidget(ProviderScope(
      overrides: [
        ordersStreamProvider.overrideWith((ref) => const Stream.empty()),
        pendingOutboxCountProvider
            .overrideWith((ref) => const Stream<int>.empty()),
        lastSyncedAtProvider
            .overrideWith((ref) => const Stream<DateTime?>.empty()),
        outboxDeadLetteredProvider.overrideWith(
            (ref) => Stream<List<OutboxData>>.value(const [])),
        pullDeadLetteredProvider.overrideWith(
            (ref) => Stream<List<PullDeadLetterData>>.value(const [])),
        // Header greets the signed-in staff; stub it explicitly so the
        // dependency is visible and never reaches the Supabase mock.
        currentStaffProvider
            .overrideWith((ref) => Stream<StaffData?>.value(null)),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: StaffDashboardScreen(retrieveLostPhoto: () async => false),
          ),
        ),
      ),
    ));
    // `LinearProgressIndicator` animates indefinitely — `pumpAndSettle` would
    // never settle.  A single `pump` is enough to build the loading frame.
    await tester.pump();

    // Loading affordance is visible.
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    // Chrome stays rendered so staff can tap straight into a new pickup.
    expect(find.byType(AnimatedGradientHeader), findsOneWidget);
    expect(find.text('New pickup'), findsOneWidget);

    // No zero-count flicker: neither the summary "Assigned" tile nor the
    // "Assigned orders" section header is in the tree during loading.
    expect(find.text('Assigned'), findsNothing);
    expect(find.text('Assigned orders', skipOffstage: false), findsNothing);
  });

  testWidgets('shows the retry button when the stream emits an error',
      (tester) async {
    // Also override the SyncStatusBanner providers + dead-letter providers
    // (read transitively via syncErrorCountProvider) to avoid hitting the
    // real file-system database — drift_flutter's driftDatabase() schedules
    // a Future at connection time, which would leave a pending Timer at
    // test teardown.
    await tester.pumpWidget(ProviderScope(
      overrides: [
        ordersStreamProvider
            .overrideWith((ref) => Stream.error(Exception('boom'))),
        pendingOutboxCountProvider
            .overrideWith((ref) => const Stream<int>.empty()),
        lastSyncedAtProvider
            .overrideWith((ref) => const Stream<DateTime?>.empty()),
        outboxDeadLetteredProvider.overrideWith(
            (ref) => Stream<List<OutboxData>>.value(const [])),
        pullDeadLetteredProvider.overrideWith(
            (ref) => Stream<List<PullDeadLetterData>>.value(const [])),
        // Header greets the signed-in staff; stub it explicitly so the
        // dependency is visible and never reaches the Supabase mock.
        currentStaffProvider
            .overrideWith((ref) => Stream<StaffData?>.value(null)),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: StaffDashboardScreen(retrieveLostPhoto: () async => false),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Could not load orders'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
  });

  testWidgets(
    'Sign-out menu item invokes the signOut callback and navigates to '
    'LoginScreen after the user confirms',
    (tester) async {
      // Critical #5: signOutAndReset is fully tested in pure-Dart but was
      // unreachable from the UI until now. This test verifies (a) the menu
      // item exists, (b) the confirmation dialog gates the action, (c) on
      // confirm the injected signOut callback fires, and (d) the dashboard
      // is replaced by the login screen.
      var signOutCalls = 0;

      // The sign-out control now lives at the bottom of the Account tab; give
      // the surface enough height that the NavigationBar does not overlap it.
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(ProviderScope(
        overrides: [
          ordersStreamProvider
              .overrideWith((ref) => Stream<List<LaundryOrder>>.value(const [])),
          pendingOutboxCountProvider
              .overrideWith((ref) => const Stream<int>.empty()),
          lastSyncedAtProvider
              .overrideWith((ref) => const Stream<DateTime?>.empty()),
          outboxDeadLetteredProvider
              .overrideWith((ref) => Stream<List<OutboxData>>.value(const [])),
          pullDeadLetteredProvider.overrideWith(
              (ref) => Stream<List<PullDeadLetterData>>.value(const [])),
          currentStaffProvider
              .overrideWith((ref) => Stream<StaffData?>.value(null)),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: StaffDashboardScreen(
                retrieveLostPhoto: () async => false,
                signOut: (ref) async {
                  signOutCalls += 1;
                },
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Open the Account tab and tap its "Sign out" button. (The button is an
      // OutlinedButton.icon, whose internal type does not match
      // find.byType(OutlinedButton); target the label text instead.)
      await tester.tap(find.text('Account').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();

      // The confirmation dialog is up; nothing has happened yet.
      expect(find.text('Sign out?'), findsOneWidget);
      expect(signOutCalls, 0);

      // Cancel first — dialog dismisses, callback NOT invoked.
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Sign out?'), findsNothing);
      expect(signOutCalls, 0);
      expect(find.byType(StaffDashboardScreen), findsOneWidget);

      // Tap the Account-tab sign-out again and this time confirm via the
      // dialog's TextButton (disambiguated from the tab button behind it).
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Sign out'));
      await tester.pumpAndSettle();

      // signOut callback fired exactly once and the LoginScreen replaced
      // the dashboard.
      expect(signOutCalls, 1);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(StaffDashboardScreen), findsNothing);
    },
  );

  testWidgets(
    'Sign-out shows a SnackBar and stays on the dashboard when the callback '
    'throws',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(ProviderScope(
        overrides: [
          ordersStreamProvider
              .overrideWith((ref) => Stream<List<LaundryOrder>>.value(const [])),
          pendingOutboxCountProvider
              .overrideWith((ref) => const Stream<int>.empty()),
          lastSyncedAtProvider
              .overrideWith((ref) => const Stream<DateTime?>.empty()),
          outboxDeadLetteredProvider
              .overrideWith((ref) => Stream<List<OutboxData>>.value(const [])),
          pullDeadLetteredProvider.overrideWith(
              (ref) => Stream<List<PullDeadLetterData>>.value(const [])),
          currentStaffProvider
              .overrideWith((ref) => Stream<StaffData?>.value(null)),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: StaffDashboardScreen(
                retrieveLostPhoto: () async => false,
                signOut: (ref) async {
                  throw Exception('orchestrator stuck');
                },
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Account').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Sign out'));
      await tester.pumpAndSettle();

      // Dashboard is still up; LoginScreen was never pushed.
      expect(find.byType(StaffDashboardScreen), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);
      // User-facing failure feedback.
      expect(find.textContaining('Could not sign out'), findsOneWidget);
      // The exception was handled, not left dangling.
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('dashboard renders header, stats and quick actions after settle',
      (tester) async {
    await pumpDashboardWithDb(tester);

    expect(find.byType(AnimatedGradientHeader), findsOneWidget);
    expect(find.text('Assigned'), findsOneWidget);
    // Quick actions are chrome; assert they're mounted regardless of the fold.
    expect(find.text('Quick actions', skipOffstage: false), findsOneWidget);
  });

  testWidgets(
      'Home tab keeps header + quick-actions chrome across the loading→data '
      'transition (progress swaps to summary, no re-mount)', (tester) async {
    // Drive the stream manually so we can observe the loading frame and then
    // the data frame. The header and quick actions must stay mounted across the
    // swap; only the middle (progress → summary) and the orders list change.
    final controller = StreamController<List<LaundryOrder>>();
    addTearDown(controller.close);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        ordersStreamProvider.overrideWith((ref) => controller.stream),
        pendingOutboxCountProvider
            .overrideWith((ref) => const Stream<int>.empty()),
        lastSyncedAtProvider
            .overrideWith((ref) => const Stream<DateTime?>.empty()),
        outboxDeadLetteredProvider
            .overrideWith((ref) => Stream<List<OutboxData>>.value(const [])),
        pullDeadLetteredProvider.overrideWith(
            (ref) => Stream<List<PullDeadLetterData>>.value(const [])),
        // Header greets the signed-in staff; stub it explicitly so the
        // dependency is visible and never reaches the Supabase mock.
        currentStaffProvider
            .overrideWith((ref) => Stream<StaffData?>.value(null)),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: StaffDashboardScreen(retrieveLostPhoto: () async => false),
          ),
        ),
      ),
    ));

    // Loading frame: header chrome + quick actions are up, progress is shown,
    // and there is no summary "Assigned" tile yet.
    await tester.pump();
    expect(find.byType(AnimatedGradientHeader), findsOneWidget);
    // Quick actions stay mounted as chrome across the swap; assert on mount,
    // not on-screen (they may sit below the fold on the test viewport).
    expect(find.text('New pickup', skipOffstage: false), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Assigned'), findsNothing);

    final headerElement = tester.element(find.byType(AnimatedGradientHeader));

    // Data arrives.
    controller.add(const []);
    await tester.pump(); // deliver the stream event
    await tester.pump(); // rebuild with data

    // Chrome stayed mounted (same Element), progress was replaced by the
    // summary grid.
    expect(find.byType(AnimatedGradientHeader), findsOneWidget);
    expect(find.text('New pickup', skipOffstage: false), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('Assigned'), findsOneWidget);
    expect(tester.element(find.byType(AnimatedGradientHeader)), same(headerElement));
  });

  testWidgets(
      'Tapping an order card without a current session refuses to open '
      'OrderDetailsScreen and surfaces a session-expired SnackBar',
      (tester) async {
    // Critical #1: when currentUserIdProvider yields null (cold-start race,
    // expired session) the dashboard must NOT push OrderDetailsScreen — its
    // downstream writes would otherwise persist an empty actorStaffId into
    // intake_recorded_by/created_by, FK-failing the outbox dispatch and
    // silently dead-lettering the row.

    // Use a tall surface so the summary card and the order card both render
    // fully on-screen, above the bottom NavigationBar.
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    const seeded = LaundryOrder(
      orderId: 'AMW-NULL',
      customerName: 'No Session',
      serviceType: ServiceType.washOnly,
      status: OrderStatus.pendingPickup,
      timeLabel: '10:00 AM',
      itemCount: 1,
      phone: 'p',
      address: 'a',
      notes: '',
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        ordersStreamProvider.overrideWith(
          (ref) => Stream<List<LaundryOrder>>.value(const [seeded]),
        ),
        pendingOutboxCountProvider
            .overrideWith((ref) => const Stream<int>.empty()),
        lastSyncedAtProvider
            .overrideWith((ref) => const Stream<DateTime?>.empty()),
        currentUserIdProvider.overrideWith((ref) => null),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child:
                StaffDashboardScreen(retrieveLostPhoto: () async => false),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // The order list no longer lives on Home — open it from the Assigned
    // summary card, then tap the order there.
    await tester.tap(find.text('Assigned'));
    await tester.pumpAndSettle();
    expect(find.byType(OrderFilterScreen), findsOneWidget);

    await tester.tap(find.text('No Session'));
    await tester.pumpAndSettle();

    // OrderDetailsScreen must not be in the tree; we stay on the filter screen.
    expect(find.byType(OrderDetailsScreen), findsNothing);
    expect(find.byType(OrderFilterScreen), findsOneWidget);
    // Session-expired SnackBar surfaced.
    expect(
      find.textContaining('Session expired'),
      findsOneWidget,
    );
  });

  // ------------------------------------------------ Tappable summary cards

  testWidgets(
    'the Home tab no longer repeats the assigned-orders list',
    (tester) async {
      const seeded = LaundryOrder(
        orderId: 'AMW-1',
        customerName: 'Home List Gone',
        serviceType: ServiceType.washOnly,
        status: OrderStatus.pendingPickup,
        timeLabel: 't',
        itemCount: 1,
        phone: 'p',
        address: 'a',
        notes: '',
      );

      await pumpDashboardWithDb(tester, extraOverrides: [
        ordersStreamProvider.overrideWith(
          (ref) => Stream<List<LaundryOrder>>.value(const [seeded]),
        ),
      ]);

      // Summary cards are present, but the order itself is not listed on Home.
      expect(find.text('Assigned'), findsOneWidget);
      expect(find.text('Assigned orders', skipOffstage: false), findsNothing);
      expect(find.text('Home List Gone'), findsNothing);
    },
  );

  testWidgets(
    'tapping a summary card opens the matching filtered screen with all of '
    'its orders',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      LaundryOrder pending(String id) => LaundryOrder(
            orderId: id,
            orderCode: id,
            customerName: 'Cust $id',
            serviceType: ServiceType.washOnly,
            status: OrderStatus.pendingPickup,
            timeLabel: 't',
            itemCount: 1,
            phone: 'p',
            address: 'a',
            notes: '',
          );

      await pumpDashboardWithDb(tester, extraOverrides: [
        ordersStreamProvider.overrideWith(
          (ref) => Stream<List<LaundryOrder>>.value(
            [pending('a'), pending('b'), pending('c')],
          ),
        ),
        currentUserIdProvider.overrideWith((ref) => 'staff-1'),
      ]);

      await tester.tap(find.text('Pending pickup'));
      await tester.pumpAndSettle();

      // Right screen, right title, and exactly the three pending orders — the
      // count on the card and the list behind it cannot disagree.
      expect(find.byType(OrderFilterScreen), findsOneWidget);
      expect(find.widgetWithText(AppBar, 'Pending pickup'), findsOneWidget);
      expect(find.byType(OrderCard), findsNWidgets(3));
    },
  );

  testWidgets(
    '"Completed today" previews only orders delivered today',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      LaundryOrder completedAt(String id, DateTime when) => LaundryOrder(
            orderId: id,
            orderCode: id,
            customerName: 'Cust $id',
            serviceType: ServiceType.washOnly,
            status: OrderStatus.completed,
            timeLabel: 't',
            itemCount: 1,
            phone: 'p',
            address: 'a',
            notes: '',
            proofEvents: [
              ProofEvent(
                id: 'd-$id',
                type: ProofEventType.delivery,
                capturedAt: when,
                count: 1,
                photoPaths: const [],
              ),
            ],
          );

      await pumpDashboardWithDb(tester, extraOverrides: [
        ordersStreamProvider.overrideWith(
          (ref) => Stream<List<LaundryOrder>>.value([
            completedAt('today', DateTime.now()),
            completedAt('old', DateTime(2020, 1, 1, 9)),
          ]),
        ),
        currentUserIdProvider.overrideWith((ref) => 'staff-1'),
      ]);

      await tester.tap(find.text('Completed today'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AppBar, 'Completed today'), findsOneWidget);
      // Only the order delivered today is previewed; the 2020 one is excluded.
      expect(find.byType(OrderCard), findsOneWidget);
      expect(find.text('Cust today'), findsOneWidget);
      expect(find.text('Cust old'), findsNothing);
    },
  );

  testWidgets(
    'summary grid cards share one height on a narrow phone, despite '
    'different label lengths',
    (tester) async {
      // 360px wide: the label column is narrow enough that "Pending pickup" /
      // "Ready for delivery" wrap while "Assigned" stays one line. The four
      // 2x2 cards must still match height (regression: "Assigned" was 100px
      // next to a 132px neighbour).
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await pumpDashboardWithDb(tester);

      double cardHeight(String title) => tester
          .getSize(find
              .ancestor(of: find.text(title), matching: find.byType(Card))
              .first)
          .height;

      final assigned = cardHeight('Assigned');
      for (final title in const [
        'Pending pickup',
        'In progress',
        'Ready for delivery',
      ]) {
        expect(cardHeight(title), assigned, reason: '$title vs Assigned');
      }
    },
  );

  testWidgets(
    'Report tab: tapping the "Pending work" card opens the matching filter',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      const seeded = LaundryOrder(
        orderId: 'P1',
        orderCode: 'P1',
        customerName: 'Pending Cust',
        serviceType: ServiceType.washOnly,
        status: OrderStatus.inProgress,
        timeLabel: 't',
        itemCount: 2,
        phone: 'p',
        address: 'a',
        notes: '',
      );

      await pumpDashboardWithDb(tester, extraOverrides: [
        ordersStreamProvider.overrideWith(
          (ref) => Stream<List<LaundryOrder>>.value(const [seeded]),
        ),
      ]);

      await tester.tap(find.text('Report').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pending work'));
      await tester.pumpAndSettle();

      expect(find.byType(OrderFilterScreen), findsOneWidget);
      expect(find.widgetWithText(AppBar, 'Pending work'), findsOneWidget);
      expect(find.text('Pending Cust'), findsOneWidget);
    },
  );

  testWidgets(
    'Report tab: tapping the "Orders" card opens a screen titled "Orders"',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      const seeded = LaundryOrder(
        orderId: 'O1',
        orderCode: 'O1',
        customerName: 'Orders Cust',
        serviceType: ServiceType.washOnly,
        status: OrderStatus.inProgress,
        timeLabel: 't',
        itemCount: 1,
        phone: 'p',
        address: 'a',
        notes: '',
      );

      await pumpDashboardWithDb(tester, extraOverrides: [
        ordersStreamProvider.overrideWith(
          (ref) => Stream<List<LaundryOrder>>.value(const [seeded]),
        ),
      ]);

      await tester.tap(find.text('Report').last);
      await tester.pumpAndSettle();
      // 'Orders' is also the bottom-nav label, so scope the tap to the report's
      // metric card.
      await tester.tap(find.descendant(
        of: find.byType(DailyReportView),
        matching: find.text('Orders'),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(OrderFilterScreen), findsOneWidget);
      expect(find.widgetWithText(AppBar, 'Orders'), findsOneWidget);
      expect(find.text('Orders Cust'), findsOneWidget);
    },
  );

  testWidgets(
    'Report tab: tapping the "Items" card opens ItemsBreakdownScreen',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      const seeded = LaundryOrder(
        orderId: 'I1',
        orderCode: 'I1',
        customerName: 'Items Cust',
        serviceType: ServiceType.washOnly,
        status: OrderStatus.inProgress,
        timeLabel: 't',
        itemCount: 4,
        phone: 'p',
        address: 'a',
        notes: '',
      );

      await pumpDashboardWithDb(tester, extraOverrides: [
        ordersStreamProvider.overrideWith(
          (ref) => Stream<List<LaundryOrder>>.value(const [seeded]),
        ),
      ]);

      await tester.tap(find.text('Report').last);
      await tester.pumpAndSettle();
      // .first: the metric card is the only 'Items' text before the screen is
      // pushed; pin it so a future 'Items' label can't make the tap ambiguous.
      await tester.tap(find.text('Items').first);
      await tester.pumpAndSettle();

      expect(find.byType(ItemsBreakdownScreen), findsOneWidget);
      expect(find.text('Total items handled today: 4'), findsOneWidget);
    },
  );

  testWidgets(
    'Report tab: tapping Add opens the expense entry screen',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await pumpDashboardWithDb(tester, extraOverrides: [
        currentUserIdProvider.overrideWith((ref) => 'staff-1'),
      ]);

      await tester.tap(find.text('Report').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Record an expense'));
      await tester.pumpAndSettle();

      expect(find.byType(ExpenseEntryScreen), findsOneWidget);
    },
  );

  testWidgets(
    'Report tab: tapping Add with a null staffId shows a session-expired '
    'SnackBar instead of opening the entry screen',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await pumpDashboardWithDb(tester, extraOverrides: [
        currentUserIdProvider.overrideWith((ref) => null),
      ]);

      await tester.tap(find.text('Report').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Record an expense'));
      await tester.pumpAndSettle();

      expect(find.byType(ExpenseEntryScreen), findsNothing);
      expect(find.text('Session expired — please sign in again.'),
          findsOneWidget);
    },
  );

  // ---------------------------------------------------------------- Plan 4 #3

  testWidgets(
    'sync-errors badge shows the combined count of outbox + pull dead-letters',
    (tester) async {
      OutboxData fakeOutboxRow(String id) => OutboxData(
            id: id, forTable: 'orders', op: 'update', rowId: 'r-$id',
            payloadJson: '{}',
            createdAt: DateTime.utc(2026, 5, 23),
            retryCount: 6,
            lastAttemptedAt: DateTime.utc(2026, 5, 23),
            lastError: 'boom',
            status: 'dead_letter',
          );
      PullDeadLetterData fakePullRow(String id) => PullDeadLetterData(
            id: id, forTable: 'orders',
            rowPayloadJson: '{}',
            errorText: 'mapper boom',
            recordedAt: DateTime.utc(2026, 5, 23),
          );

      await pumpDashboardWithDb(tester, extraOverrides: [
        outboxDeadLetteredProvider.overrideWith((ref) =>
            Stream<List<OutboxData>>.value([
              fakeOutboxRow('a'),
              fakeOutboxRow('b'),
            ])),
        pullDeadLetteredProvider.overrideWith((ref) =>
            Stream<List<PullDeadLetterData>>.value([
              fakePullRow('p1'),
              fakePullRow('p2'),
              fakePullRow('p3'),
            ])),
      ]);

      // Badge label text equals the combined count (2 + 3).
      expect(find.byTooltip('Sync errors'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
    },
    // Online-only mode: the sync-errors badge was removed from the dashboard
    // AppBar (no outbox/dead-letter queue online).
    skip: true,
  );

  testWidgets(
    'tapping the sync-errors badge opens SyncErrorsScreen',
    (tester) async {
      await pumpDashboardWithDb(tester);

      await tester.tap(find.byTooltip('Sync errors'));
      await tester.pumpAndSettle();

      expect(find.byType(SyncErrorsScreen), findsOneWidget);
    },
    // Online-only mode: the sync-errors badge/screen entry point was removed
    // from the dashboard AppBar.
    skip: true,
  );

  // ---------------------------------------------- Pricing entry role-gating

  testWidgets(
    'Account tab hides Pricing settings for the driver role (write-gated)',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await pumpDashboardWithDb(tester, extraOverrides: [
        currentRoleProvider.overrideWith((ref) => 'driver'),
      ]);

      await tester.tap(find.text('Account').last);
      await tester.pumpAndSettle();

      expect(find.text('Pricing settings'), findsNothing);
      // The Account tab still rendered (sign-out is always present).
      expect(find.text('Sign out'), findsOneWidget);
    },
  );

  testWidgets(
    'Account tab shows Pricing settings for the manager role',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await pumpDashboardWithDb(tester, extraOverrides: [
        currentRoleProvider.overrideWith((ref) => 'manager'),
      ]);

      await tester.tap(find.text('Account').last);
      await tester.pumpAndSettle();

      expect(find.text('Pricing settings'), findsOneWidget);
      // The Role row now reflects the real role, not a hardcoded string.
      expect(find.text('Manager'), findsOneWidget);
    },
  );

  testWidgets(
    'Account tab shows Pricing settings for the in_shop role',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await pumpDashboardWithDb(tester, extraOverrides: [
        currentRoleProvider.overrideWith((ref) => 'in_shop'),
      ]);

      await tester.tap(find.text('Account').last);
      await tester.pumpAndSettle();

      expect(find.text('Pricing settings'), findsOneWidget);
    },
  );
}
