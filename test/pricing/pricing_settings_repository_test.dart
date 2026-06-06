import 'package:flutter_test/flutter_test.dart';
import 'package:amuwak_staff/src/pricing/pricing_settings.dart';
import 'package:amuwak_staff/src/pricing/pricing_settings_repository.dart';

void main() {
  group('PricingSettingsRepository', () {
    test('throws a clear error when no settings row exists', () async {
      final repo = PricingSettingsRepository.forTest(fetchRows: () async => []);
      expect(repo.fetch, throwsA(isA<StateError>()));
    });

    test('returns the first row when present', () async {
      final repo = PricingSettingsRepository.forTest(fetchRows: () async => [
            {
              'id': 'p1',
              'default_rate_per_kg_ugx': 5000,
              'updated_at': '2026-06-06T10:00:00Z',
              'updated_by': null,
            }
          ]);
      final s = await repo.fetch();
      expect(s.defaultRatePerKgUgx, 5000);
    });
  });
}
