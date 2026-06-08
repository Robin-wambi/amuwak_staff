import 'package:flutter_test/flutter_test.dart';
import 'package:amuwak_staff/src/pricing/pricing_settings.dart';

void main() {
  group('PricingSettings', () {
    test('fromSupabase reads the singleton row', () {
      final s = PricingSettings.fromSupabase({
        'id': 'p1',
        'default_rate_per_kg_ugx': 5000,
        'updated_at': '2026-06-06T10:00:00Z',
        'updated_by': 'staff-1',
      });
      expect(s.id, 'p1');
      expect(s.defaultRatePerKgUgx, 5000);
    });

    test('reads an integer-typed rate as double', () {
      final s = PricingSettings.fromSupabase({
        'id': 'p1',
        'default_rate_per_kg_ugx': 4500,
        'updated_at': '2026-06-06T10:00:00Z',
        'updated_by': null,
      });
      expect(s.defaultRatePerKgUgx, 4500.0);
    });
  });
}
