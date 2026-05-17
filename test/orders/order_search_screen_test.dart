import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_staff/src/orders/order_search_screen.dart';

void main() {
  testWidgets('OrderSearchScreen shows the empty state', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: OrderSearchScreen()),
    );

    expect(find.text('Order search'), findsOneWidget);
    expect(find.text('Order search coming soon.'), findsOneWidget);
    expect(
      find.text('For now, browse orders on the dashboard.'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.search_off_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
