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

    test('is not equal when name or amount differ, and not equal to other types',
        () {
      expect(LineItem(name: 'A', amountUgx: 100) ==
          LineItem(name: 'B', amountUgx: 100), isFalse);
      expect(LineItem(name: 'A', amountUgx: 100) ==
          LineItem(name: 'A', amountUgx: 200), isFalse);
      // ignore: unrelated_type_equality_checks
      expect(LineItem(name: 'A', amountUgx: 100) == 'A', isFalse);
    });

    test('equal items share a hashCode; different items usually do not', () {
      expect(LineItem(name: 'A', amountUgx: 100).hashCode,
          LineItem(name: 'A', amountUgx: 100).hashCode);
      expect(LineItem(name: 'A', amountUgx: 100).hashCode,
          isNot(LineItem(name: 'B', amountUgx: 100).hashCode));
    });

    test('toString includes the name and amount', () {
      expect(LineItem(name: 'Blanket', amountUgx: 8000).toString(),
          'LineItem(Blanket, 8000)');
    });
  });
}
