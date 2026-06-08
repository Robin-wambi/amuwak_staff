import 'package:flutter_test/flutter_test.dart';
import 'package:amuwak_staff/src/shared/format_ugx.dart';

void main() {
  group('formatUgx', () {
    test('adds thousands separators and the USh prefix', () {
      expect(formatUgx(8000), 'USh 8,000');
      expect(formatUgx(1500000), 'USh 1,500,000');
    });

    test('handles values below 1000 with no separator', () {
      expect(formatUgx(0), 'USh 0');
      expect(formatUgx(500), 'USh 500');
    });

    test('formats negative values (e.g. a discount preview)', () {
      expect(formatUgx(-5000), 'USh -5,000');
    });
  });
}
