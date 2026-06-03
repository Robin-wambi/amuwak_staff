import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_staff/src/orders/proof/barcode_reader.dart';
import 'package:amuwak_staff/src/orders/proof/scanner_screen.dart';

Future<bool?> _pumpAndPushScanner(
  WidgetTester tester, {
  required String expectedOrderId,
  required String scannedValue,
}) async {
  bool? result;

  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          return Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => ScannerScreen(
                        expectedOrderId: expectedOrderId,
                        cameraViewBuilder: (ctx, onDetected) {
                          return FakeCameraView(
                            scannedValue: scannedValue,
                            onDetected: onDetected,
                          );
                        },
                      ),
                    ),
                  );
                },
                child: const Text('Open scanner'),
              ),
            ),
          );
        },
      ),
    ),
  );

  await tester.tap(find.text('Open scanner'));
  await tester.pumpAndSettle();
  return Future.value(result);
}

void main() {
  testWidgets('matching scanned value pops the screen with true',
      (tester) async {
    await _pumpAndPushScanner(
      tester,
      expectedOrderId: 'AMW-1',
      scannedValue: 'AMW-1',
    );

    await tester.tap(find.text('Simulate scan'));
    await tester.pumpAndSettle();

    expect(find.byType(ScannerScreen), findsNothing);
  });

  testWidgets('wrong scanned value shows an error and stays on screen',
      (tester) async {
    await _pumpAndPushScanner(
      tester,
      expectedOrderId: 'AMW-1',
      scannedValue: 'AMW-9',
    );

    await tester.tap(find.text('Simulate scan'));
    await tester.pump();

    expect(find.byType(ScannerScreen), findsOneWidget);
    expect(find.textContaining('AMW-9'), findsOneWidget);
    expect(find.textContaining('AMW-1'), findsOneWidget);
  });

  testWidgets(
      'a new-format code is recognised as an order tag, not a generic value',
      (tester) async {
    await _pumpAndPushScanner(
      tester,
      expectedOrderId: 'AMW-2026-0099',
      scannedValue: 'AMW-2026-0042',
    );

    await tester.tap(find.text('Simulate scan'));
    await tester.pump();

    expect(find.byType(ScannerScreen), findsOneWidget);
    // The year-dash-counter form must trip the "belongs to order #..."
    // wording, not the generic "does not match" fallback.
    expect(
      find.textContaining('belongs to order #AMW-2026-0042'),
      findsOneWidget,
    );
  });

  testWidgets('manual entry path: matching id pops with true', (tester) async {
    await _pumpAndPushScanner(
      tester,
      expectedOrderId: 'AMW-1',
      scannedValue: 'unused',
    );

    await tester.tap(find.text('Enter order ID instead'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'AMW-1');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Submit'));
    await tester.pumpAndSettle();

    expect(find.byType(ScannerScreen), findsNothing);
  });

  testWidgets('manual entry path: wrong id shows error', (tester) async {
    await _pumpAndPushScanner(
      tester,
      expectedOrderId: 'AMW-1',
      scannedValue: 'unused',
    );

    await tester.tap(find.text('Enter order ID instead'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'AMW-9');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Submit'));
    await tester.pump();

    expect(find.byType(ScannerScreen), findsOneWidget);
    expect(find.textContaining('AMW-9'), findsOneWidget);
  });

  testWidgets(
    'scanning a non-order-id value shows a generic mismatch error',
    (tester) async {
      await _pumpAndPushScanner(
        tester,
        expectedOrderId: 'AMW-1',
        scannedValue: 'https://example.com',
      );

      await tester.tap(find.text('Simulate scan'));
      await tester.pump();

      expect(find.byType(ScannerScreen), findsOneWidget);
      // Must NOT use the "belongs to order #..." phrasing for a random value.
      expect(find.textContaining('belongs to order'), findsNothing);
      expect(find.textContaining('https://example.com'), findsNothing);
      // Generic mismatch references only the expected order.
      expect(
        find.textContaining('does not match order #AMW-1'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'empty manual submit shows a generic mismatch error',
    (tester) async {
      await _pumpAndPushScanner(
        tester,
        expectedOrderId: 'AMW-1',
        scannedValue: 'unused',
      );

      await tester.tap(find.text('Enter order ID instead'));
      await tester.pumpAndSettle();

      // Submit with the field still empty.
      await tester.tap(find.widgetWithText(ElevatedButton, 'Submit'));
      await tester.pump();

      expect(find.byType(ScannerScreen), findsOneWidget);
      expect(find.textContaining('belongs to order'), findsNothing);
      expect(
        find.textContaining('does not match order #AMW-1'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'manual entry path: lowercase id for an uppercase order matches',
    (tester) async {
      await _pumpAndPushScanner(
        tester,
        expectedOrderId: 'AMW-1024',
        scannedValue: 'unused',
      );

      await tester.tap(find.text('Enter order ID instead'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), 'amw-1024');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Submit'));
      await tester.pumpAndSettle();

      expect(find.byType(ScannerScreen), findsNothing);
    },
  );

  testWidgets(
    'repeated detections after a match do not pop the screen twice',
    (tester) async {
      bool? result;
      var pushCount = 0;
      late OnBarcodeDetected captured;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      pushCount++;
                      result = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (_) => ScannerScreen(
                            expectedOrderId: 'AMW-1',
                            cameraViewBuilder: (ctx, onDetected) {
                              captured = onDetected;
                              return const SizedBox.shrink();
                            },
                          ),
                        ),
                      );
                    },
                    child: const Text('Open scanner'),
                  ),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Open scanner'));
      await tester.pumpAndSettle();

      // MobileScanner fires onDetect continuously while a QR code is in the
      // camera frame, including after the first matching detection has been
      // forwarded. Simulate two calls in rapid succession.
      captured('AMW-1');
      captured('AMW-1');
      await tester.pumpAndSettle();

      expect(result, isTrue);
      // Wrapper screen with the launch button must still be present — i.e. the
      // second pop must have been suppressed.
      expect(find.text('Open scanner'), findsOneWidget);
      expect(pushCount, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
