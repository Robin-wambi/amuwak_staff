import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:amuwak_staff/src/orders/proof/qr_display_widget.dart';

void main() {
  testWidgets('QrDisplayWidget renders a QrImageView with the given data',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: QrDisplayWidget(data: 'AMW-0421', size: 200),
        ),
      ),
    );

    final qrFinder = find.byType(QrImageView);
    expect(qrFinder, findsOneWidget);

    final qr = tester.widget<QrImageView>(qrFinder);
    expect(qr.size, equals(200));
  });
}
