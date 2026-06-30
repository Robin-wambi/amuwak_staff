import 'package:amuwak_core/amuwak_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // UUID string layout: xxxxxxxx-xxxx-Vxxx-Nxxx-xxxxxxxxxxxx
  //   index 14 = version nibble, index 19 = variant nibble.
  group('defaultUuidV7', () {
    test('produces a version-7, RFC-variant UUID', () {
      final id = defaultUuidV7();

      expect(id, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-'
          r'[0-9a-f]{4}-[0-9a-f]{12}$')));
      expect(id[14], '7', reason: 'version nibble must be 7');
      expect('89ab'.contains(id[19]), isTrue,
          reason: 'variant nibble must be 8/9/a/b');
    });

    test('mints distinct ids on successive calls', () {
      expect(defaultUuidV7(), isNot(defaultUuidV7()));
    });
  });
}
