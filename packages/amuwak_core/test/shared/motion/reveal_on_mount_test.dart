import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_core/amuwak_core.dart';

void main() {
  testWidgets('child is fully opaque after the reveal settles',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: RevealOnMount(child: Text('hello'))),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('hello'), findsOneWidget);
    final opacity = tester.widget<Opacity>(
      find.ancestor(of: find.text('hello'), matching: find.byType(Opacity)),
    );
    expect(opacity.opacity, 1.0);
  });

  testWidgets('honours the delay before revealing', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RevealOnMount(
            delay: Duration(milliseconds: 200),
            child: Text('delayed'),
          ),
        ),
      ),
    );

    // Immediately after mount, before the delay elapses, it is not yet visible.
    await tester.pump();
    final opacity = tester.widget<Opacity>(
      find.ancestor(of: find.text('delayed'), matching: find.byType(Opacity)),
    );
    expect(opacity.opacity, 0.0);

    await tester.pumpAndSettle();
    final settled = tester.widget<Opacity>(
      find.ancestor(of: find.text('delayed'), matching: find.byType(Opacity)),
    );
    expect(settled.opacity, 1.0);
  });

  testWidgets('reduced motion shows the child immediately (no Opacity wrapper)',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) => MediaQuery(
            data: MediaQuery.of(c).copyWith(disableAnimations: true),
            child: const Scaffold(body: RevealOnMount(child: Text('instant'))),
          ),
        ),
      ),
    );

    await tester.pump();
    expect(find.text('instant'), findsOneWidget);
    expect(
      find.ancestor(of: find.text('instant'), matching: find.byType(Opacity)),
      findsNothing,
    );
  });
}
