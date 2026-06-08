import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:amuwak_staff/src/pricing/pricing_settings.dart';
import 'package:amuwak_staff/src/pricing/pricing_settings_screen.dart';

void main() {
  testWidgets('renders the current default rate and saves a new value',
      (tester) async {
    double? saved;
    await tester.pumpWidget(MaterialApp(
      home: PricingSettingsScreen(
        load: () async => PricingSettings(
          id: 'p1',
          defaultRatePerKgUgx: 5000,
          updatedAt: DateTime.utc(2026, 6, 6),
        ),
        save: (rate) async => saved = rate,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('5000'), findsOneWidget); // pre-filled
    await tester.enterText(find.byKey(const Key('settings_rate')), '6000');
    await tester.tap(find.byKey(const Key('settings_save')));
    await tester.pump();
    expect(saved, 6000);
  });

  testWidgets('saves a fractional rate rounded so it matches the shown value',
      (tester) async {
    double? saved;
    await tester.pumpWidget(MaterialApp(
      home: PricingSettingsScreen(
        load: () async => PricingSettings(
          id: 'p1',
          defaultRatePerKgUgx: 5000,
          updatedAt: DateTime.utc(2026, 6, 6),
        ),
        save: (rate) async => saved = rate,
      ),
    ));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('settings_rate')), '5000.7');
    await tester.tap(find.byKey(const Key('settings_save')));
    await tester.pump();
    // The saved value must equal what the confirmation snackbar displays.
    expect(saved, 5001);
    expect(find.text('Default rate set to USh 5,001/kg.'), findsOneWidget);
  });
}
