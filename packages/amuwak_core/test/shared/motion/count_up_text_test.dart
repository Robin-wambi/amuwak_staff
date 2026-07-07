import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_core/amuwak_core.dart';

void main() {
  testWidgets('counts up to the target value after settle', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: CountUpText(value: 7))),
    );

    await tester.pumpAndSettle();
    expect(find.text('7'), findsOneWidget);
  });

  testWidgets('reduced motion shows the final value immediately',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) => MediaQuery(
            data: MediaQuery.of(c).copyWith(disableAnimations: true),
            child: const Scaffold(body: CountUpText(value: 42)),
          ),
        ),
      ),
    );

    await tester.pump();
    expect(find.text('42'), findsOneWidget);
  });

  testWidgets('animates to a new value when it changes', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: CountUpText(value: 3))),
    );
    await tester.pumpAndSettle();
    expect(find.text('3'), findsOneWidget);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: CountUpText(value: 9))),
    );
    await tester.pumpAndSettle();
    expect(find.text('9'), findsOneWidget);
  });
}
