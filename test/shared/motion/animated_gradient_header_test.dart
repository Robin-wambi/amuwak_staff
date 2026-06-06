import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_staff/src/shared/motion/animated_gradient_header.dart';

void main() {
  testWidgets('renders its child', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AnimatedGradientHeader(child: Text('header'))),
      ),
    );

    // The sheen repeats forever — pump a frame, do NOT pumpAndSettle.
    await tester.pump();
    expect(find.text('header'), findsOneWidget);

    // The gradient paints onto a Container decoration.
    final container = tester.widget<Container>(
      find.ancestor(of: find.text('header'), matching: find.byType(Container)),
    );
    final decoration = container.decoration as BoxDecoration;
    expect(decoration.gradient, isA<LinearGradient>());
  });

  testWidgets('reduced motion settles (no repeating ticker) and shows child',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) => MediaQuery(
            data: MediaQuery.of(c).copyWith(disableAnimations: true),
            child: const Scaffold(
              body: AnimatedGradientHeader(child: Text('static')),
            ),
          ),
        ),
      ),
    );

    // If the controller were repeating, this would time out.
    await tester.pumpAndSettle();
    expect(find.text('static'), findsOneWidget);
  });
}
