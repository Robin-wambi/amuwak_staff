import 'package:amuwak_staff/src/shared/order_code.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseOrderCodeRpcResult', () {
    test('returns a bare scalar string unchanged', () {
      expect(parseOrderCodeRpcResult('AMW-2026-0042'), 'AMW-2026-0042');
    });

    test('unwraps the PostgREST row-set form [{col: value}]', () {
      expect(
        parseOrderCodeRpcResult([
          {'next_order_code': 'AMW-2026-0042'}
        ]),
        'AMW-2026-0042',
      );
    });

    test('unwraps a single-object form {col: value}', () {
      expect(
        parseOrderCodeRpcResult({'next_order_code': 'AMW-2026-0042'}),
        'AMW-2026-0042',
      );
    });

    test('throws a descriptive error on an unexpected shape', () {
      expect(() => parseOrderCodeRpcResult(42), throwsStateError);
      expect(() => parseOrderCodeRpcResult(null), throwsStateError);
      expect(() => parseOrderCodeRpcResult(const []), throwsStateError);
    });
  });
}
