import 'package:flutter_test/flutter_test.dart';
import 'package:amuwak_staff/src/orders/pricing/line_item.dart';
import 'package:amuwak_staff/src/orders/pricing/pricing_inputs.dart';
import 'package:amuwak_staff/src/orders/pricing/pricing_calculator.dart';

void main() {
  group('recomputeTotal', () {
    test('zero weight and no line items yields zero, provisional', () {
      final t = recomputeTotal(PricingInputs(ratePerKgUgx: 5000));
      expect(t.weightCharge, 0);
      expect(t.lineItemsSum, 0);
      expect(t.total, 0);
      expect(t.isProvisional, isTrue);
    });

    test('bills on final weight when present (not provisional)', () {
      final t = recomputeTotal(PricingInputs(
        ratePerKgUgx: 5000,
        estimatedWeightKg: 3,
        finalWeightKg: 4,
      ));
      expect(t.weightCharge, 20000); // 4 * 5000
      expect(t.isProvisional, isFalse);
    });

    test('falls back to estimate when no final weight (provisional)', () {
      final t = recomputeTotal(PricingInputs(
        ratePerKgUgx: 5000,
        estimatedWeightKg: 3,
      ));
      expect(t.weightCharge, 15000); // 3 * 5000
      expect(t.isProvisional, isTrue);
    });

    test('rounds the weight charge half-up, once', () {
      // 2.5kg * 3333 = 8332.5 -> 8333
      final t = recomputeTotal(
          PricingInputs(ratePerKgUgx: 3333, finalWeightKg: 2.5));
      expect(t.weightCharge, 8333);
    });

    test('adds line items to the weight charge', () {
      final t = recomputeTotal(PricingInputs(
        ratePerKgUgx: 5000,
        finalWeightKg: 2,
        lineItems: [
          LineItem(name: 'Blanket', amountUgx: 8000),
          LineItem(name: 'Jacket', amountUgx: 5000),
        ],
      ));
      expect(t.lineItemsSum, 13000);
      expect(t.total, 23000); // 10000 + 13000
    });

    test('a negative manual adjustment reduces the total', () {
      final t = recomputeTotal(PricingInputs(
        ratePerKgUgx: 5000,
        finalWeightKg: 4,
        manualAdjustmentUgx: -5000,
      ));
      expect(t.total, 15000); // 20000 - 5000
    });

    test('total is clamped at 0 when the adjustment overshoots', () {
      final t = recomputeTotal(PricingInputs(
        ratePerKgUgx: 5000,
        finalWeightKg: 1,
        manualAdjustmentUgx: -999999,
      ));
      expect(t.total, 0);
    });
  });
}
