import 'package:flutter_test/flutter_test.dart';
import 'package:amuwak_staff/src/pricing/catalog_item.dart';

void main() {
  group('CatalogItem', () {
    test('fromSupabase reads a row', () {
      final c = CatalogItem.fromSupabase({
        'id': 'c1',
        'name': 'Blanket',
        'amount_ugx': 8000,
        'active': true,
        'sort_order': 2,
      });
      expect(c.id, 'c1');
      expect(c.name, 'Blanket');
      expect(c.amountUgx, 8000);
      expect(c.active, isTrue);
      expect(c.sortOrder, 2);
    });

    test('degrades missing active/sort_order to defaults', () {
      final c = CatalogItem.fromSupabase({
        'id': 'c1',
        'name': 'Duvet',
        'amount_ugx': 10000,
      });
      expect(c.active, isTrue);
      expect(c.sortOrder, 0);
    });

    test('toSupabase round-trips', () {
      final c = CatalogItem(
        id: 'c1',
        name: 'Jacket',
        amountUgx: 5000,
        active: false,
        sortOrder: 3,
      );
      final back = CatalogItem.fromSupabase(c.toSupabase());
      expect(back, c);
    });

    test('trims the name and rejects an empty one', () {
      expect(CatalogItem(id: 'c1', name: '  Shirt  ', amountUgx: 1000).name,
          'Shirt');
      expect(() => CatalogItem(id: 'c1', name: '   ', amountUgx: 1000),
          throwsArgumentError);
    });

    test('rejects a negative amount', () {
      expect(() => CatalogItem(id: 'c1', name: 'Shirt', amountUgx: -1),
          throwsArgumentError);
    });

    test('copyWith overrides only the given fields', () {
      final c = CatalogItem(id: 'c1', name: 'Shirt', amountUgx: 1000)
          .copyWith(active: false);
      expect(c.active, isFalse);
      expect(c.name, 'Shirt');
      expect(c.amountUgx, 1000);
    });
  });
}
