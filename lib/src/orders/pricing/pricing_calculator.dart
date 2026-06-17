import 'pricing_inputs.dart';

/// The single source of truth for an order's total. Pure, deterministic, no I/O.
///
/// weight_to_bill    = final ?? estimate ?? 0
/// weight_charge     = round_half_up(weight_to_bill * rate)   (once, not per line)
/// line_items_sum    = Σ line item amounts
/// express_surcharge = isExpress
///                       ? round_half_up(flat + pct% * (weight_charge + line_items))
///                       : 0
/// total             = max(0, weight_charge + line_items_sum
///                            + express_surcharge + delivery_fee + manual_adjustment)
///
/// The express percentage is on weight charge + line items only — delivery and
/// the manual adjustment are excluded. Manual adjustment is applied last so a
/// discount can still reduce the total, which is clamped at zero.
///
/// Rounding is half-up (matches a phone calculator the rider might run), not
/// banker's rounding. The order is provisional until a final weight is set.
OrderTotal recomputeTotal(PricingInputs inputs) {
  final weightToBill =
      inputs.finalWeightKg ?? inputs.estimatedWeightKg ?? 0;
  final weightCharge = _roundHalfUp(weightToBill * inputs.ratePerKgUgx);
  final lineItemsSum =
      inputs.lineItems.fold<int>(0, (sum, item) => sum + item.amountUgx);
  final expressBase = weightCharge + lineItemsSum;
  final expressSurcharge = inputs.isExpress
      ? _roundHalfUp(inputs.expressFlatUgx + inputs.expressPct / 100 * expressBase)
      : 0;
  final raw = weightCharge +
      lineItemsSum +
      expressSurcharge +
      inputs.deliveryFeeUgx +
      inputs.manualAdjustmentUgx;
  return OrderTotal(
    weightCharge: weightCharge,
    lineItemsSum: lineItemsSum,
    expressSurcharge: expressSurcharge,
    deliveryFee: inputs.deliveryFeeUgx,
    total: raw < 0 ? 0 : raw,
    isProvisional: inputs.finalWeightKg == null,
  );
}

/// Half-up rounding for non-negative values: (x + 0.5).floor(). All callers feed
/// values constrained to >= 0 (weights, rates, amounts); the assert pins that
/// precondition so a future negative input fails loudly in debug rather than
/// rounding the wrong way.
int _roundHalfUp(double x) {
  assert(x >= 0, '_roundHalfUp expects a non-negative value, got $x');
  return (x + 0.5).floor();
}
