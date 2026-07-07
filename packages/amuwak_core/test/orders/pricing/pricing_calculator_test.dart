import 'package:flutter_test/flutter_test.dart';
import 'package:amuwak_core/amuwak_core.dart';

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

    test('delivery fee is added to the total', () {
      final t = recomputeTotal(PricingInputs(
        ratePerKgUgx: 5000,
        finalWeightKg: 2,
        deliveryFeeUgx: 3000,
      ));
      expect(t.deliveryFee, 3000);
      expect(t.total, 13000); // 10000 + 3000
    });

    test('express off (default) adds no surcharge', () {
      final t = recomputeTotal(PricingInputs(
        ratePerKgUgx: 5000,
        finalWeightKg: 2,
        // express config present but isExpress defaults to false
        expressFlatUgx: 2000,
        expressPct: 30,
      ));
      expect(t.expressSurcharge, 0);
      expect(t.total, 10000);
    });

    test('express flat-only surcharge', () {
      final t = recomputeTotal(PricingInputs(
        ratePerKgUgx: 5000,
        finalWeightKg: 2,
        isExpress: true,
        expressFlatUgx: 2000,
      ));
      expect(t.expressSurcharge, 2000);
      expect(t.total, 12000); // 10000 + 2000
    });

    test('express percentage is on weight charge + line items', () {
      final t = recomputeTotal(PricingInputs(
        ratePerKgUgx: 5000,
        finalWeightKg: 2, // weight charge 10000
        lineItems: [LineItem(name: 'Blanket', amountUgx: 5000)],
        isExpress: true,
        expressPct: 30, // 30% of (10000 + 5000) = 4500
      ));
      expect(t.expressSurcharge, 4500);
      expect(t.total, 19500); // 15000 + 4500
    });

    test('express combines flat + percentage', () {
      final t = recomputeTotal(PricingInputs(
        ratePerKgUgx: 5000,
        finalWeightKg: 2, // 10000
        isExpress: true,
        expressFlatUgx: 2000,
        expressPct: 30, // 30% of 10000 = 3000
      ));
      expect(t.expressSurcharge, 5000); // 2000 + 3000
      expect(t.total, 15000);
    });

    test('express percentage excludes delivery fee and manual adjustment', () {
      final t = recomputeTotal(PricingInputs(
        ratePerKgUgx: 5000,
        finalWeightKg: 2, // 10000
        isExpress: true,
        expressPct: 50, // 50% of 10000 only = 5000 (NOT of delivery/adjustment)
        deliveryFeeUgx: 4000,
        manualAdjustmentUgx: 1000,
      ));
      expect(t.expressSurcharge, 5000);
      expect(t.total, 20000); // 10000 + 5000 + 4000 + 1000
    });

    test('express surcharge rounds half-up', () {
      // 33% of 10000 = 3300; use a base that yields a .5
      // weight charge 10000, pct 33.335 -> 3333.5 -> 3334
      final t = recomputeTotal(PricingInputs(
        ratePerKgUgx: 5000,
        finalWeightKg: 2,
        isExpress: true,
        expressPct: 33.335,
      ));
      expect(t.expressSurcharge, 3334);
    });

    test('full breakdown: weight + items + express + delivery + adjustment', () {
      final t = recomputeTotal(PricingInputs(
        ratePerKgUgx: 5000,
        finalWeightKg: 2, // 10000
        lineItems: [LineItem(name: 'Duvet', amountUgx: 5000)],
        isExpress: true,
        expressFlatUgx: 1000,
        expressPct: 20, // 20% of (10000 + 5000) = 3000; + flat 1000 = 4000
        deliveryFeeUgx: 3000,
        manualAdjustmentUgx: -2000,
      ));
      expect(t.weightCharge, 10000);
      expect(t.lineItemsSum, 5000);
      expect(t.expressSurcharge, 4000);
      expect(t.deliveryFee, 3000);
      expect(t.total, 20000); // 10000 + 5000 + 4000 + 3000 - 2000
    });
  });
}
