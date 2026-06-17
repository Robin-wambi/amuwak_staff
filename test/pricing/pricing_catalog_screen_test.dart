import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:amuwak_staff/src/pricing/catalog_item.dart';
import 'package:amuwak_staff/src/pricing/pricing_catalog_screen.dart';

void main() {
  Widget screen({
    required List<CatalogItem> items,
    required void Function(CatalogItem) onSave,
    String newId = 'new-id',
  }) {
    // Reload returns the same list; tests assert on the saved item, not reload.
    return MaterialApp(
      home: PricingCatalogScreen(
        load: () async => items,
        save: (item) async => onSave(item),
        idGenerator: () => newId,
      ),
    );
  }

  testWidgets('lists items and marks retired ones', (tester) async {
    await tester.pumpWidget(screen(
      items: [
        CatalogItem(id: 'c1', name: 'Blanket', amountUgx: 8000),
        CatalogItem(id: 'c2', name: 'Old', amountUgx: 5000, active: false),
      ],
      onSave: (_) {},
    ));
    await tester.pumpAndSettle();
    expect(find.text('Blanket'), findsOneWidget);
    expect(find.text('Old'), findsOneWidget);
    expect(find.text('Retired'), findsOneWidget);
  });

  testWidgets('shows an empty state when there are no items', (tester) async {
    await tester.pumpWidget(screen(items: const [], onSave: (_) {}));
    await tester.pumpAndSettle();
    expect(find.text('No service items yet.'), findsOneWidget);
  });

  testWidgets('adds a new active item with a generated id', (tester) async {
    CatalogItem? saved;
    await tester.pumpWidget(screen(
      items: const [],
      onSave: (item) => saved = item,
      newId: 'gen-1',
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('catalog_add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('catalog_name')), 'Duvet');
    await tester.enterText(find.byKey(const Key('catalog_amount')), '10000');
    await tester.tap(find.byKey(const Key('catalog_save')));
    await tester.pumpAndSettle();
    expect(saved, isNotNull);
    expect(saved!.id, 'gen-1');
    expect(saved!.name, 'Duvet');
    expect(saved!.amountUgx, 10000);
    expect(saved!.active, isTrue);
  });

  testWidgets('editing an item can retire it', (tester) async {
    CatalogItem? saved;
    await tester.pumpWidget(screen(
      items: [CatalogItem(id: 'c1', name: 'Blanket', amountUgx: 8000)],
      onSave: (item) => saved = item,
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('catalog_item_0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('catalog_active'))); // turn off
    await tester.tap(find.byKey(const Key('catalog_save')));
    await tester.pumpAndSettle();
    expect(saved, isNotNull);
    expect(saved!.id, 'c1');
    expect(saved!.active, isFalse);
  });

  testWidgets('rejects a blank name', (tester) async {
    CatalogItem? saved;
    await tester.pumpWidget(screen(items: const [], onSave: (i) => saved = i));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('catalog_add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('catalog_amount')), '5000');
    await tester.tap(find.byKey(const Key('catalog_save')));
    await tester.pumpAndSettle();
    expect(saved, isNull);
    expect(find.text('Enter an item name'), findsOneWidget);
  });
}
