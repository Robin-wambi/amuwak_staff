import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:amuwak_staff/src/orders/pricing/line_item.dart';
import 'package:amuwak_staff/src/orders/pricing/pricing_section.dart';

void main() {
  testWidgets('LineItemsEditor shows items and fires onRemove', (tester) async {
    var removed = -1;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LineItemsEditor(
          items: [LineItem(name: 'Blanket', amountUgx: 8000)],
          onAdd: () {},
          onRemove: (i) => removed = i,
        ),
      ),
    ));
    expect(find.text('Blanket'), findsOneWidget);
    expect(find.text('USh 8,000'), findsOneWidget);
    await tester.tap(find.byKey(const Key('remove_line_item_0')));
    expect(removed, 0);
  });

  testWidgets('TotalCard renders the total and a Provisional badge', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: TotalCard(totalUgx: 23000, isProvisional: true),
      ),
    ));
    expect(find.text('USh 23,000'), findsOneWidget);
    expect(find.text('Provisional'), findsOneWidget);
  });

  testWidgets(
      'showAddLineItemSheet keeps the sheet open and shows an error on invalid amount',
      (tester) async {
    LineItem? result;
    var returned = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await showAddLineItemSheet(context);
              returned = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('line_item_name')), 'Blanket');
    await tester.enterText(find.byKey(const Key('line_item_amount')), 'abc');
    await tester.tap(find.byKey(const Key('line_item_save')));
    await tester.pumpAndSettle();

    // Sheet stays open with a validation message; nothing returned yet.
    expect(returned, isFalse);
    expect(find.byKey(const Key('line_item_amount')), findsOneWidget);
    expect(find.text('Enter a valid amount'), findsOneWidget);

    // Correcting the amount and saving returns the item.
    await tester.enterText(find.byKey(const Key('line_item_amount')), '8000');
    await tester.tap(find.byKey(const Key('line_item_save')));
    await tester.pumpAndSettle();

    expect(returned, isTrue);
    expect(result, isNotNull);
    expect(result!.name, 'Blanket');
    expect(result!.amountUgx, 8000);
  });
}
