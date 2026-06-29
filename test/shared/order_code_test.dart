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

    test('falls back to the sole value for a single-column row without the '
        'named key', () {
      // PostgREST sometimes labels the scalar column generically; with only one
      // column and no next_order_code key, the sole value is the code.
      expect(
        parseOrderCodeRpcResult({'?column?': 'AMW-2026-0042'}),
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

    test(
        'throws when next_order_code is present but null, instead of falling '
        'back to another column', () {
      // A present-but-null code key must fail loudly, not silently return some
      // other column's value (here 'x') as if it were the order code.
      expect(
          () => parseOrderCodeRpcResult([
                {'other_col': 'x', 'next_order_code': null}
              ]),
          throwsStateError);
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

  group('orderCodeNumber', () {
    test('extracts the counter from the current AMW-YYYY-NNNN form', () {
      expect(orderCodeNumber('AMW-2026-0042'), 42);
    });

    test('extracts the digits from the legacy AMW-NNNN form', () {
      expect(orderCodeNumber('AMW-1024'), 1024);
    });

    test('parses a bare number a rider types, ignoring leading zeros', () {
      expect(orderCodeNumber('0042'), 42);
      expect(orderCodeNumber('42'), 42);
      expect(orderCodeNumber('4'), 4);
    });

    test('is case-insensitive and tolerates surrounding whitespace', () {
      expect(orderCodeNumber('  amw-2026-0007  '), 7);
    });

    test('returns null when there is no trailing digit run', () {
      expect(orderCodeNumber(''), isNull);
      expect(orderCodeNumber('   '), isNull);
      expect(orderCodeNumber('AMW-'), isNull);
      expect(orderCodeNumber('abc'), isNull);
    });
  });

  group('isBareOrderNumber', () {
    test('is true for digits only, with or without leading zeros', () {
      expect(isBareOrderNumber('4'), isTrue);
      expect(isBareOrderNumber('0042'), isTrue);
    });

    test('is false for a formatted code or anything non-numeric', () {
      expect(isBareOrderNumber('AMW-2026-0042'), isFalse);
      expect(isBareOrderNumber('AMW-1024'), isFalse);
      expect(isBareOrderNumber('42a'), isFalse);
      expect(isBareOrderNumber(''), isFalse);
    });

    test('tolerates whitespace, staying aligned with int.tryParse', () {
      // int.tryParse also accepts a padded number, so the predicate must too —
      // otherwise the gate and the parse in searchBy could disagree.
      expect(isBareOrderNumber('  42  '), isTrue);
      expect(int.tryParse('  42  '), 42);
    });
  });
}
