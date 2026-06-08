import 'package:flutter_test/flutter_test.dart';
import 'package:amuwak_staff/src/orders/pricing/line_item.dart';

void main() {
  group('LineItem', () {
    test('constructs with a trimmed name and non-negative amount', () {
      final item = LineItem(name: '  Blanket ', amountUgx: 8000);
      expect(item.name, 'Blanket');
      expect(item.amountUgx, 8000);
    });

    test('rejects an empty or whitespace-only name', () {
      expect(() => LineItem(name: '', amountUgx: 1000), throwsArgumentError);
      expect(() => LineItem(name: '   ', amountUgx: 1000), throwsArgumentError);
    });

    test('rejects a negative amount', () {
      expect(() => LineItem(name: 'Jacket', amountUgx: -1), throwsArgumentError);
    });

    test('round-trips through JSON', () {
      final item = LineItem(name: 'Jacket', amountUgx: 5000);
      expect(LineItem.fromJson(item.toJson()), item);
    });

    test('fromJson reads a Supabase jsonb map', () {
      final item = LineItem.fromJson({'name': 'Duvet', 'amount_ugx': 12000});
      expect(item.name, 'Duvet');
      expect(item.amountUgx, 12000);
    });

    test('value equality', () {
      expect(
        LineItem(name: 'A', amountUgx: 100),
        LineItem(name: 'A', amountUgx: 100),
      );
    });
  });
}
