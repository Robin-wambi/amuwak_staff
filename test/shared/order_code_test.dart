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

    test('targets the next_order_code key when the row has other columns', () {
      // The first column is NOT the code — a naive values.first would wrongly
      // return 'x'. We must key on next_order_code.
      expect(
        parseOrderCodeRpcResult([
          {'other_col': 'x', 'next_order_code': 'AMW-2026-0042'}
        ]),
        'AMW-2026-0042',
      );
    });

    test('throws a descriptive error on an unexpected shape', () {
      expect(() => parseOrderCodeRpcResult(42), throwsStateError);
      expect(() => parseOrderCodeRpcResult(null), throwsStateError);
      expect(() => parseOrderCodeRpcResult(const []), throwsStateError);
      // A list/map carrying a non-string payload is still an unexpected shape.
      expect(() => parseOrderCodeRpcResult(const [42]), throwsStateError);
    });

    test('throws on an empty or blank code rather than storing garbage', () {
      expect(() => parseOrderCodeRpcResult(''), throwsStateError);
      expect(() => parseOrderCodeRpcResult('   '), throwsStateError);
      expect(
          () => parseOrderCodeRpcResult([
                {'next_order_code': ''}
              ]),
          throwsStateError);
    });
  });
}
