import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_staff/src/orders/proof/proof_photo_storage.dart';
import 'package:amuwak_staff/src/orders/proof_event.dart';

void main() {
  group('InMemoryProofPhotoStorage', () {
    test('save returns a unique-looking path that encodes order, type, index',
        () async {
      final storage = InMemoryProofPhotoStorage();

      final path = await storage.save(
        orderId: 'AMW-0421',
        type: ProofEventType.pickup,
        index: 0,
        bytes: const [1, 2, 3],
      );

      expect(path, contains('AMW-0421'));
      expect(path, contains('pickup'));
      expect(path, contains('0'));
    });

    test('save retains the bytes and path in savedPhotos', () async {
      final storage = InMemoryProofPhotoStorage();

      final path = await storage.save(
        orderId: 'AMW-1',
        type: ProofEventType.delivery,
        index: 2,
        bytes: const [9, 8, 7],
      );

      expect(storage.savedPhotos, hasLength(1));
      expect(storage.savedPhotos.single.path, equals(path));
      expect(storage.savedPhotos.single.bytes, equals(const [9, 8, 7]));
    });
  });
}
