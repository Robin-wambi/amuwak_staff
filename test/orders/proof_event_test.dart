import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_staff/src/orders/proof_event.dart';

void main() {
  final pickedAt = DateTime(2026, 5, 12, 9, 42);

  group('ProofEvent', () {
    test('two ProofEvents with identical fields are equal', () {
      final a = ProofEvent(
        type: ProofEventType.pickup,
        capturedAt: pickedAt,
        count: 12,
        photoPaths: const ['a.jpg', 'b.jpg'],
        notes: 'gate locked',
      );
      final b = ProofEvent(
        type: ProofEventType.pickup,
        capturedAt: pickedAt,
        count: 12,
        photoPaths: const ['a.jpg', 'b.jpg'],
        notes: 'gate locked',
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('different type makes events unequal', () {
      final a = ProofEvent(
        type: ProofEventType.pickup,
        capturedAt: pickedAt,
        count: 12,
        photoPaths: const ['a.jpg'],
      );
      final b = ProofEvent(
        type: ProofEventType.delivery,
        capturedAt: pickedAt,
        count: 12,
        photoPaths: const ['a.jpg'],
      );

      expect(a, isNot(equals(b)));
    });

    test('different photoPaths order makes events unequal', () {
      final a = ProofEvent(
        type: ProofEventType.pickup,
        capturedAt: pickedAt,
        count: 1,
        photoPaths: const ['a.jpg', 'b.jpg'],
      );
      final b = ProofEvent(
        type: ProofEventType.pickup,
        capturedAt: pickedAt,
        count: 1,
        photoPaths: const ['b.jpg', 'a.jpg'],
      );

      expect(a, isNot(equals(b)));
    });

    test('notes default to null when omitted', () {
      final a = ProofEvent(
        type: ProofEventType.pickup,
        capturedAt: pickedAt,
        count: 1,
        photoPaths: const [],
      );

      expect(a.notes, isNull);
    });
  });
}
