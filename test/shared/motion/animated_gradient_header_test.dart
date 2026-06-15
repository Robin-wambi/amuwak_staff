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

  testWidgets('reacts to reduce-motion toggled at runtime', (tester) async {
    final reduceMotion = ValueNotifier<bool>(true);
    addTearDown(reduceMotion.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ValueListenableBuilder<bool>(
              valueListenable: reduceMotion,
              builder: (context, reduce, _) => MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
                child: const AnimatedGradientHeader(child: Text('header')),
              ),
            ),
          ),
        ),
      ),
    );

    // Reduced motion: the ticker is idle, so the tree settles.
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);

    // Toggle off: the sheen resumes, so a frame is always scheduled.
    reduceMotion.value = false;
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isTrue);

    // Toggle back on: the sheen freezes and the tree settles again.
    reduceMotion.value = true;
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
