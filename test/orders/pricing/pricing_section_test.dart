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
}
