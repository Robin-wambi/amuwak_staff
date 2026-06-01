import 'package:amuwak_staff/src/shared/theme/app_card.dart';
import 'package:amuwak_staff/src/shared/theme/app_radii.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
}
