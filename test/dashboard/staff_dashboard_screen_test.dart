import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_staff/src/dashboard/staff_dashboard_screen.dart';

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
}
