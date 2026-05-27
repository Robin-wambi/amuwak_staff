import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_staff/src/auth/login_screen.dart';
import 'package:amuwak_staff/src/auth/session.dart';
import 'package:amuwak_staff/src/dashboard/staff_dashboard_screen.dart';
import 'package:amuwak_staff/src/notifications/notifications_screen.dart';
import 'package:amuwak_staff/src/orders/new_pickup_screen.dart';
import 'package:amuwak_staff/src/orders/order.dart';
import 'package:amuwak_staff/src/orders/order_details_screen.dart';
import 'package:amuwak_staff/src/orders/order_search_screen.dart';
import 'package:amuwak_staff/src/orders/order_status.dart';
import 'package:amuwak_staff/src/orders/service_type.dart';
import 'package:amuwak_staff/src/data/app_database.dart';
import 'package:amuwak_staff/src/shared/widgets/sync_status_banner.dart';
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
Future<void> pumpDashboardWithDb(
  WidgetTester tester, {
  bool lostPhoto = false,
  List<Override> extraOverrides = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // Provide a trivial in-memory implementation of every Drift-backed
        // stream so that no real Drift stream subscriptions are opened.
        pendingOutboxCountProvider
            .overrideWith((ref) => const Stream<int>.empty()),
        lastSyncedAtProvider
            .overrideWith((ref) => const Stream<DateTime?>.empty()),
        ordersStreamProvider
            .overrideWith((ref) => Stream<List<LaundryOrder>>.value(const [])),
        outboxDeadLetteredProvider.overrideWith(
            (ref) => Stream<List<OutboxData>>.value(const [])),
        pullDeadLetteredProvider.overrideWith(
            (ref) => Stream<List<PullDeadLetterData>>.value(const [])),
        ...extraOverrides,
      ],
      child: MaterialApp(
        home: StaffDashboardScreen(retrieveLostPhoto: () async => lostPhoto),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
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

      await tester.ensureVisible(find.text('New pickup'));
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

      await tester.ensureVisible(find.text('New pickup'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New pickup'));
      await tester.pumpAndSettle();

      expect(find.byType(NewPickupScreen), findsNothing);
      expect(find.text('Session expired — please sign in again.'),
          findsOneWidget);
    },
  );

  testWidgets(
    'Tapping "Check order" opens OrderSearchScreen',
    (tester) async {
      await pumpDashboardWithDb(tester);

      await tester.ensureVisible(find.text('Check order'));
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
      final headerTop = tester.getTopLeft(find.text('Welcome back'));
      expect(bannerTop.dy, lessThan(headerTop.dy));
    });
  });

  // ------------------------------------------------------------------ Task 9

  testWidgets('renders an order card for each row in ordersStreamProvider',
      (tester) async {
    // Seed a single order through the stream and verify the dashboard
    // renders a card for it.  `Stream.value` emits synchronously on subscribe
    // so the first `pumpAndSettle` after `pumpWidget` is enough.
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

    await tester.pumpWidget(ProviderScope(
      overrides: [
        ordersStreamProvider.overrideWith(
          (ref) => Stream<List<LaundryOrder>>.value(const [seeded]),
        ),
        pendingOutboxCountProvider
            .overrideWith((ref) => const Stream<int>.empty()),
        lastSyncedAtProvider
            .overrideWith((ref) => const Stream<DateTime?>.empty()),
      ],
      child: MaterialApp(
          home: StaffDashboardScreen(retrieveLostPhoto: () async => false)),
    ));
    await tester.pumpAndSettle();

    // The customer name is in the card; `skipOffstage: false` because cards
    // sit below the visible viewport in the lazy ListView on the default
    // 800x600 test surface.
    expect(find.text('Test', skipOffstage: false), findsOneWidget);
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
      ],
      child: MaterialApp(
          home: StaffDashboardScreen(retrieveLostPhoto: () async => false)),
    ));
    // `LinearProgressIndicator` animates indefinitely — `pumpAndSettle` would
    // never settle.  A single `pump` is enough to build the loading frame.
    await tester.pump();

    // Loading affordance is visible.
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    // Chrome stays rendered so staff can tap straight into a new pickup.
    expect(find.text('Staff Workspace'), findsOneWidget);
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
      ],
      child: MaterialApp(
          home: StaffDashboardScreen(retrieveLostPhoto: () async => false)),
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

      await tester.pumpWidget(ProviderScope(
        overrides: [
          ordersStreamProvider
              .overrideWith((ref) => Stream<List<LaundryOrder>>.value(const [])),
          pendingOutboxCountProvider
              .overrideWith((ref) => const Stream<int>.empty()),
          lastSyncedAtProvider
              .overrideWith((ref) => const Stream<DateTime?>.empty()),
        ],
        child: MaterialApp(
          home: StaffDashboardScreen(
            retrieveLostPhoto: () async => false,
            signOut: (ref) async {
              signOutCalls += 1;
            },
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Open the account menu and tap "Sign out".
      await tester.tap(find.byTooltip('Account'));
      await tester.pumpAndSettle();
      expect(find.text('Sign out'), findsOneWidget);
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

      // Open the menu again and this time confirm.
      await tester.tap(find.byTooltip('Account'));
      await tester.pumpAndSettle();
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
      await tester.pumpWidget(ProviderScope(
        overrides: [
          ordersStreamProvider
              .overrideWith((ref) => Stream<List<LaundryOrder>>.value(const [])),
          pendingOutboxCountProvider
              .overrideWith((ref) => const Stream<int>.empty()),
          lastSyncedAtProvider
              .overrideWith((ref) => const Stream<DateTime?>.empty()),
        ],
        child: MaterialApp(
          home: StaffDashboardScreen(
            retrieveLostPhoto: () async => false,
            signOut: (ref) async {
              throw Exception('orchestrator stuck');
            },
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Account'));
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

  testWidgets(
      'Tapping an order card without a current session refuses to open '
      'OrderDetailsScreen and surfaces a session-expired SnackBar',
      (tester) async {
    // Critical #1: when currentUserIdProvider yields null (cold-start race,
    // expired session) the dashboard must NOT push OrderDetailsScreen — its
    // downstream writes would otherwise persist an empty actorStaffId into
    // intake_recorded_by/created_by, FK-failing the outbox dispatch and
    // silently dead-lettering the row.
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
          home: StaffDashboardScreen(retrieveLostPhoto: () async => false)),
    ));
    await tester.pumpAndSettle();

    // Tap the card. ListView is lazy so we need to scroll the card on-screen
    // first.
    await tester.scrollUntilVisible(find.text('No Session'), 200);
    await tester.tap(find.text('No Session'));
    await tester.pumpAndSettle();

    // OrderDetailsScreen must not be in the tree.
    expect(find.byType(OrderDetailsScreen), findsNothing);
    // Dashboard is still visible.
    expect(find.byType(StaffDashboardScreen), findsOneWidget);
    // Session-expired SnackBar surfaced.
    expect(
      find.textContaining('Session expired'),
      findsOneWidget,
    );
  });

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
  );

  testWidgets(
    'tapping the sync-errors badge opens SyncErrorsScreen',
    (tester) async {
      await pumpDashboardWithDb(tester);

      await tester.tap(find.byTooltip('Sync errors'));
      await tester.pumpAndSettle();

      expect(find.byType(SyncErrorsScreen), findsOneWidget);
    },
  );
}
