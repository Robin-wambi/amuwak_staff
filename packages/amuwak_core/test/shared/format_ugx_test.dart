import 'package:flutter_test/flutter_test.dart';
import 'package:amuwak_core/amuwak_core.dart';

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

  group('formatPct', () {
    test('renders a whole percentage without decimals', () {
      expect(formatPct(30.0), '30');
      expect(formatPct(0.0), '0');
    });

    test('keeps a real fraction', () {
      expect(formatPct(12.5), '12.5');
    });

    test('treats float noise near a whole number as whole', () {
      // A value that should be a whole 30 but carries tiny float error from
      // upstream arithmetic must still render as "30", not "30.000000000001".
      expect(formatPct(30.0 + 1e-12), '30');
    });
  });
}
