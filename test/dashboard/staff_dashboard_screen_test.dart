import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_staff/src/dashboard/staff_dashboard_screen.dart';
import 'package:amuwak_staff/src/notifications/notifications_screen.dart';
import 'package:amuwak_staff/src/orders/new_pickup_screen.dart';
import 'package:amuwak_staff/src/orders/order_search_screen.dart';

void main() {
  testWidgets(
    'Surfaces a SnackBar on startup when an in-flight photo capture was lost',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: StaffDashboardScreen(
            retrieveLostPhoto: () async => true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('photo capture was interrupted'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Does not show the lost-capture SnackBar when nothing was lost',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: StaffDashboardScreen(
            retrieveLostPhoto: () async => false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('photo capture was interrupted'),
        findsNothing,
      );
    },
  );

  testWidgets(
    'Tapping the bell opens NotificationsScreen',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: StaffDashboardScreen(
            retrieveLostPhoto: () async => false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Notifications'));
      await tester.pumpAndSettle();

      expect(find.byType(NotificationsScreen), findsOneWidget);
    },
  );

  testWidgets(
    'Tapping "New pickup" opens NewPickupScreen',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: StaffDashboardScreen(
            retrieveLostPhoto: () async => false,
          ),
        ),
      );
      await tester.pumpAndSettle();

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
      await tester.pumpWidget(
        MaterialApp(
          home: StaffDashboardScreen(
            retrieveLostPhoto: () async => false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Check order'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Check order'));
      await tester.pumpAndSettle();

      expect(find.byType(OrderSearchScreen), findsOneWidget);
    },
  );
}
