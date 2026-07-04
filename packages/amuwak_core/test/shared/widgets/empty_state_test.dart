import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_core/amuwak_core.dart';

void main() {
  testWidgets('EmptyState renders the icon, headline, and subtitle',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EmptyState(
            icon: Icons.inbox_outlined,
            headline: 'Nothing here.',
            subtitle: 'Check back later.',
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);
    expect(find.text('Nothing here.'), findsOneWidget);
    expect(find.text('Check back later.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
