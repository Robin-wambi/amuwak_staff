import 'package:amuwak_staff/src/shared/motion/garment_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A placeholder item builder that renders the garment label as plain text,
/// so the tests don't depend on real SVG asset loading.
Widget _labelBuilder(BuildContext context, Garment garment) =>
    Center(child: Text(garment.label));

/// Wraps [child] in a MaterialApp, overriding the platform reduce-motion flag
/// while preserving the test surface size so the PageView can lay out.
Widget _host(Widget child, {required bool reduceMotion}) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
          child: SizedBox(height: 84, child: child),
        ),
      ),
    ),
  );
}

void main() {
  group('GarmentStrip', () {
    testWidgets('renders the first garment', (tester) async {
      await tester.pumpWidget(
        _host(
          GarmentStrip(itemBuilder: _labelBuilder),
          reduceMotion: false,
        ),
      );

      expect(find.text(GarmentStrip.defaultGarments.first.label), findsOneWidget);
    });

    testWidgets('auto-advances to the next garment when motion is allowed',
        (tester) async {
      int? lastPage;
      await tester.pumpWidget(
        _host(
          GarmentStrip(
            itemBuilder: _labelBuilder,
            onPageChanged: (i) => lastPage = i,
          ),
          reduceMotion: false,
        ),
      );

      // Advance past the auto-advance interval, then let the slide settle.
      await tester.pump(const Duration(milliseconds: 2800));
      await tester.pump(const Duration(milliseconds: 600));

      expect(lastPage, 1);
    });

    testWidgets('reverses at the last garment instead of rewinding to the first',
        (tester) async {
      final pages = <int>[];
      await tester.pumpWidget(
        _host(
          GarmentStrip(
            itemBuilder: _labelBuilder,
            onPageChanged: pages.add,
          ),
          reduceMotion: false,
        ),
      );

      // Drive enough auto-advances to reach the last page and step past it.
      final count = GarmentStrip.defaultGarments.length;
      for (var i = 0; i < count + 3; i++) {
        await tester.pump(const Duration(milliseconds: 2800));
        await tester.pump(const Duration(milliseconds: 600));
      }

      // It walks 0→…→last, then steps back to last-1 rather than jumping to 0.
      final peak = pages.indexOf(count - 1);
      expect(peak, greaterThanOrEqualTo(0)); // reached the last garment
      expect(pages[peak + 1], count - 2); // reversed, not rewound to 0
    });

    testWidgets('does not auto-advance when reduce-motion is on',
        (tester) async {
      int? lastPage;
      await tester.pumpWidget(
        _host(
          GarmentStrip(
            itemBuilder: _labelBuilder,
            onPageChanged: (i) => lastPage = i,
          ),
          reduceMotion: true,
        ),
      );

      await tester.pump(const Duration(milliseconds: 2800));
      await tester.pump(const Duration(milliseconds: 600));

      expect(lastPage, isNull);
    });

    testWidgets('reacts to reduce-motion toggled off then on at runtime',
        (tester) async {
      final reduceMotion = ValueNotifier<bool>(true);
      addTearDown(reduceMotion.dispose);
      int? lastPage;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ValueListenableBuilder<bool>(
                valueListenable: reduceMotion,
                builder: (context, reduce, _) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
                  child: SizedBox(
                    height: 84,
                    child: GarmentStrip(
                      itemBuilder: _labelBuilder,
                      onPageChanged: (i) => lastPage = i,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      // Reduced motion: no auto-advance.
      await tester.pump(const Duration(milliseconds: 2800));
      await tester.pump(const Duration(milliseconds: 600));
      expect(lastPage, isNull);

      // Toggle the preference off; the same strip should begin advancing.
      reduceMotion.value = false;
      await tester.pump(); // rebuild -> didChangeDependencies starts the timer
      await tester.pump(const Duration(milliseconds: 2800));
      await tester.pump(const Duration(milliseconds: 600));
      expect(lastPage, 1);

      // Toggle it back on; the timer is cancelled, so it stops advancing.
      reduceMotion.value = true;
      await tester.pump(); // rebuild -> didChangeDependencies cancels the timer
      await tester.pump(const Duration(milliseconds: 2800));
      await tester.pump(const Duration(milliseconds: 600));
      expect(lastPage, 1); // unchanged
    });

    testWidgets('pauses while its subtree is muted, resumes when revealed',
        (tester) async {
      final ticking = ValueNotifier<bool>(false);
      addTearDown(ticking.dispose);
      int? lastPage;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ValueListenableBuilder<bool>(
                valueListenable: ticking,
                builder: (context, enabled, _) => TickerMode(
                  enabled: enabled,
                  child: SizedBox(
                    height: 84,
                    child: GarmentStrip(
                      itemBuilder: _labelBuilder,
                      onPageChanged: (i) => lastPage = i,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      // Muted (e.g. obscured by a pushed route): no auto-advance even though
      // reduce-motion is off.
      await tester.pump(const Duration(milliseconds: 2800));
      await tester.pump(const Duration(milliseconds: 600));
      expect(lastPage, isNull);

      // Revealed again: the strip resumes advancing.
      ticking.value = true;
      await tester.pump(); // rebuild -> didChangeDependencies starts the timer
      await tester.pump(const Duration(milliseconds: 2800));
      await tester.pump(const Duration(milliseconds: 600));
      expect(lastPage, 1);
    });
  });
}
