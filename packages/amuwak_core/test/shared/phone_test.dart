import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_core/amuwak_core.dart';

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

  group('ugandaNationalDigits', () {
    test('strips the +256 country code to the 9-digit national number', () {
      expect(ugandaNationalDigits('+256 700 123 456'), '700123456');
      expect(ugandaNationalDigits('256700123456'), '700123456');
    });

    test('strips a single leading 0 (local trunk prefix)', () {
      expect(ugandaNationalDigits('0700123456'), '700123456');
    });

    test('leaves a bare national number unchanged', () {
      expect(ugandaNationalDigits('700123456'), '700123456');
      expect(ugandaNationalDigits('700 123 456'), '700123456');
    });

    test('returns empty when there are no national digits', () {
      expect(ugandaNationalDigits('+256 '), '');
      expect(ugandaNationalDigits('0'), '');
      expect(ugandaNationalDigits(''), '');
    });

    test('a local and an international form reduce to the same value', () {
      expect(
        ugandaNationalDigits('0700123456'),
        ugandaNationalDigits('+256 700 123 456'),
      );
    });

    test('strips a redundant trunk 0 written after the +256 country code', () {
      // A rider who types their local 0-number after the "+256 " prefill, or a
      // stored "+256 0700..." form, must still reduce to the 9-digit national
      // number — otherwise it is 10 digits and never matches / never validates.
      expect(ugandaNationalDigits('+256 0700 123 456'), '700123456');
      expect(ugandaNationalDigits('2560700123456'), '700123456');
    });
  });
}
