import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_staff/src/auth/session.dart';
import 'package:amuwak_staff/src/dashboard/staff_dashboard_screen.dart';
import 'package:amuwak_staff/src/notifications/notifications_screen.dart';
import 'package:amuwak_staff/src/orders/new_pickup_screen.dart';
import 'package:amuwak_staff/src/orders/order.dart';
import 'package:amuwak_staff/src/orders/order_details_screen.dart';
import 'package:amuwak_staff/src/orders/order_search_screen.dart';
import 'package:amuwak_staff/src/orders/order_status.dart';
import 'package:amuwak_staff/src/shared/widgets/sync_status_banner.dart';
import 'package:amuwak_staff/src/sync/repository_providers.dart';
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
      await pumpDashboardWithDb(tester);

      await tester.ensureVisible(find.text('New pickup'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New pickup'));
      await tester.pumpAndSettle();

      expect(find.byType(NewPickupScreen), findsOneWidget);
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
      serviceType: 'wash',
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
    // are also stubbed so no real Drift stream is opened.
    await tester.pumpWidget(ProviderScope(
      overrides: [
        ordersStreamProvider.overrideWith((ref) => const Stream.empty()),
        pendingOutboxCountProvider
            .overrideWith((ref) => const Stream<int>.empty()),
        lastSyncedAtProvider
            .overrideWith((ref) => const Stream<DateTime?>.empty()),
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
    // Also override the SyncStatusBanner providers to avoid hitting the real
    // file-system database.
    await tester.pumpWidget(ProviderScope(
      overrides: [
        ordersStreamProvider
            .overrideWith((ref) => Stream.error(Exception('boom'))),
        pendingOutboxCountProvider
            .overrideWith((ref) => const Stream<int>.empty()),
        lastSyncedAtProvider
            .overrideWith((ref) => const Stream<DateTime?>.empty()),
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
      serviceType: 'wash',
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
}
