import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_core/amuwak_core.dart';

void main() {
  group('isValidEmail', () {
    test('accepts a well-formed address', () {
      expect(isValidEmail('rider@amuwak.co.ug'), isTrue);
      expect(isValidEmail('a.b+tag@example.com'), isTrue);
    });

    test('trims surrounding whitespace before checking', () {
      expect(isValidEmail('  rider@amuwak.co  '), isTrue);
    });

    test('rejects addresses missing the local or domain part', () {
      expect(isValidEmail('a@'), isFalse);
      expect(isValidEmail('@b.com'), isFalse);
      expect(isValidEmail('plainaddress'), isFalse);
    });

    test('rejects a domain with no dot', () {
      expect(isValidEmail('rider@localhost'), isFalse);
    });

    test('rejects internal whitespace and multiple @', () {
      expect(isValidEmail('ri der@amuwak.co'), isFalse);
      expect(isValidEmail('a@b@c.com'), isFalse);
    });

    test('rejects the empty string', () {
      expect(isValidEmail(''), isFalse);
      expect(isValidEmail('   '), isFalse);
    });
  });
}
