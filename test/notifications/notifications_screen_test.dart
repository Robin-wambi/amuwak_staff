import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_staff/src/notifications/notifications_screen.dart';

void main() {
  testWidgets('NotificationsScreen shows the empty state', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: NotificationsScreen()),
    );

    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('No notifications yet.'), findsOneWidget);
    expect(
      find.text("We'll let you know when something needs your attention."),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.notifications_off_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
