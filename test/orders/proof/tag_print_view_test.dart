import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_staff/src/orders/proof/printable_tag.dart';
import 'package:amuwak_staff/src/orders/proof/tag_print_view.dart';
import 'package:amuwak_staff/src/printing/label_printer.dart';

import '../../helpers/fake_label_printer.dart';

final _tagBytes = Uint8List.fromList(const [7, 7, 7, 7]);

Future<void> _pump(
  WidgetTester tester, {
  required LabelPrinter? printer,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: TagPrintView(
          orderCode: 'AMW-2026-0042',
          customerName: 'Jane Doe',
          labelPrinter: printer,
          captureTag: (_) async => _tagBytes,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('always shows the tag preview', (tester) async {
    await _pump(tester, printer: null);
    expect(find.byType(PrintableTag), findsOneWidget);
    expect(find.text('AMW-2026-0042'), findsOneWidget);
  });

  testWidgets('hides the print button when no printer is wired up',
      (tester) async {
    await _pump(tester, printer: null);
    expect(find.byKey(const Key('print_tag')), findsNothing);
  });

  testWidgets('prints when a printer is already connected', (tester) async {
    final printer = FakeLabelPrinter(
      connected: const PrinterDevice(id: 'AB:CD', name: 'Munbyn'),
    );
    await _pump(tester, printer: printer);

    await tester.tap(find.byKey(const Key('print_tag')));
    await tester.pumpAndSettle();

    expect(printer.printed, hasLength(1));
    expect(printer.printed.single, equals(_tagBytes));
  });

  testWidgets('picks a printer when none is connected, then prints',
      (tester) async {
    final printer = FakeLabelPrinter(
      devices: const [PrinterDevice(id: 'AB:CD', name: 'Phomemo M2')],
    );
    await _pump(tester, printer: printer);

    await tester.tap(find.byKey(const Key('print_tag')));
    await tester.pumpAndSettle();
    expect(find.text('Phomemo M2'), findsOneWidget);

    await tester.tap(find.text('Phomemo M2'));
    await tester.pumpAndSettle();

    expect(printer.connectCalls, hasLength(1));
    expect(printer.printed, hasLength(1));
  });

  testWidgets('guides the rider when no printer is paired', (tester) async {
    final printer = FakeLabelPrinter();
    await _pump(tester, printer: printer);

    await tester.tap(find.byKey(const Key('print_tag')));
    await tester.pumpAndSettle();

    expect(printer.printed, isEmpty);
    expect(find.textContaining('No paired printer'), findsOneWidget);
  });

  testWidgets('surfaces an error and re-enables the button on print failure',
      (tester) async {
    final printer = FakeLabelPrinter(
      connected: const PrinterDevice(id: 'AB:CD', name: 'Munbyn'),
      printThrows: Exception('offline'),
    );
    await _pump(tester, printer: printer);

    await tester.tap(find.byKey(const Key('print_tag')));
    await tester.pumpAndSettle();

    expect(printer.printed, isEmpty);
    expect(find.textContaining('Could not print the tag'), findsOneWidget);
    final button = tester.widget<OutlinedButton>(
      find.byKey(const Key('print_tag')),
    );
    expect(button.onPressed, isNotNull);
  });
}
