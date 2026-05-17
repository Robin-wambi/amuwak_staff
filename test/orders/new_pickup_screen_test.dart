import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_staff/src/orders/new_pickup_screen.dart';

void main() {
  testWidgets('NewPickupScreen shows the empty state', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: NewPickupScreen()),
    );

    expect(find.text('New pickup'), findsOneWidget);
    expect(find.text('New pickup will land here soon.'), findsOneWidget);
    expect(
      find.text('For now, pickups come from the dashboard list.'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.add_location_alt_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
