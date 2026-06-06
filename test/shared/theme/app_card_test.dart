import 'package:amuwak_staff/src/shared/motion/pressable_scale.dart';
import 'package:amuwak_staff/src/shared/theme/app_card.dart';
import 'package:amuwak_staff/src/shared/theme/app_elevation.dart';
import 'package:amuwak_staff/src/shared/theme/app_radii.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  BoxDecoration? shadowDecoration(WidgetTester tester) {
    for (final box
        in tester.widgetList<DecoratedBox>(find.byType(DecoratedBox))) {
      final decoration = box.decoration;
      if (decoration is BoxDecoration &&
          (decoration.boxShadow?.isNotEmpty ?? false)) {
        return decoration;
      }
    }
    return null;
  }

  testWidgets('AppCard renders its child inside a Card with the card radius',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AppCard(child: Text('hello'))),
      ),
    );

    expect(find.text('hello'), findsOneWidget);
    final card = tester.widget<Card>(find.byType(Card));
    final shape = card.shape as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.circular(AppRadii.card));
  });

  testWidgets('AppCard without onTap inserts no InkWell', (tester) async {
    // A non-interactive card should not carry an inert InkWell in the tree.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AppCard(child: Text('plain'))),
      ),
    );

    expect(find.byType(InkWell), findsNothing);
    expect(find.text('plain'), findsOneWidget);
  });

  testWidgets('AppCard onTap makes it tappable', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppCard(onTap: () => tapped = true, child: const Text('tap')),
        ),
      ),
    );
    await tester.tap(find.text('tap'));
    expect(tapped, isTrue);
  });

  testWidgets('paints the resting elevation shadow', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AppCard(child: Text('content'))),
      ),
    );

    final decoration = shadowDecoration(tester);
    expect(decoration, isNotNull);
    expect(decoration!.boxShadow, AppElevation.resting);
  });

  testWidgets('keeps the shadow when tappable', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppCard(onTap: () {}, child: const Text('tap')),
        ),
      ),
    );

    expect(shadowDecoration(tester), isNotNull);
  });

  testWidgets('tappable AppCard scales via PressableScale', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppCard(onTap: () {}, child: const Text('press')),
        ),
      ),
    );

    expect(find.byType(PressableScale), findsOneWidget);
  });
}
