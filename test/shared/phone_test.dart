import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_staff/src/shared/phone.dart';

void main() {
  group('normalizePhone', () {
    test('strips spaces, +, and country-code punctuation to digits only', () {
      expect(normalizePhone('+256 700 123 456'), '256700123456');
      expect(normalizePhone('(0700) 123-456'), '0700123456');
      expect(normalizePhone('0700123456'), '0700123456');
    });

    test('returns an empty string when there are no digits', () {
      expect(normalizePhone(''), '');
      expect(normalizePhone('  +- '), '');
    });
  });
}
