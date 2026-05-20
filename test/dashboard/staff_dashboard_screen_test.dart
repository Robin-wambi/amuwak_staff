import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_staff/src/dashboard/staff_dashboard_screen.dart';
import 'package:amuwak_staff/src/notifications/notifications_screen.dart';
import 'package:amuwak_staff/src/orders/new_pickup_screen.dart';
import 'package:amuwak_staff/src/orders/order_search_screen.dart';
import 'package:amuwak_staff/src/shared/widgets/sync_status_banner.dart';
import 'package:amuwak_staff/src/sync/sync_status.dart';

/// Pumps StaffDashboardScreen inside a ProviderScope. Lets each test
/// override sync providers without restating the boilerplate.
Future<void> _pumpDashboard(
  WidgetTester tester, {
  bool lostPhoto = false,
  List<Override> overrides = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        home: StaffDashboardScreen(
          retrieveLostPhoto: () async => lostPhoto,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Surfaces a SnackBar on startup when an in-flight photo capture was lost',
    (tester) async {
      await _pumpDashboard(tester, lostPhoto: true);

      expect(
        find.textContaining('photo capture was interrupted'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Does not show the lost-capture SnackBar when nothing was lost',
    (tester) async {
      await _pumpDashboard(tester);

      expect(
        find.textContaining('photo capture was interrupted'),
        findsNothing,
      );
    },
  );

  testWidgets(
    'Tapping the bell opens NotificationsScreen',
    (tester) async {
      await _pumpDashboard(tester);

      await tester.tap(find.byTooltip('Notifications'));
      await tester.pumpAndSettle();

      expect(find.byType(NotificationsScreen), findsOneWidget);
    },
  );

  testWidgets(
    'Tapping "New pickup" opens NewPickupScreen',
    (tester) async {
      await _pumpDashboard(tester);

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
      await _pumpDashboard(tester);

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
      await _pumpDashboard(tester, overrides: [
        onlineProvider.overrideWith((ref) => false),
      ]);

      expect(find.byType(SyncStatusBanner), findsOneWidget);
      expect(find.textContaining('Offline'), findsOneWidget);
    });

    testWidgets(
      'renders the pending-uploads banner with the count when online',
      (tester) async {
        await _pumpDashboard(tester, overrides: [
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
        await _pumpDashboard(tester, overrides: [
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
      await _pumpDashboard(tester, overrides: [
        onlineProvider.overrideWith((ref) => false),
      ]);

      final bannerTop = tester.getTopLeft(find.byType(SyncStatusBanner));
      final headerTop = tester.getTopLeft(find.text('Welcome back'));
      expect(bannerTop.dy, lessThan(headerTop.dy));
    });
  });
}
