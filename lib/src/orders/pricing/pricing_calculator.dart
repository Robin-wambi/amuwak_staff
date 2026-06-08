import 'pricing_inputs.dart';

/// The single source of truth for an order's total. Pure, deterministic, no I/O.
///
/// weight_to_bill   = final ?? estimate ?? 0
/// weight_charge    = round_half_up(weight_to_bill * rate)   (once, not per line)
/// line_items_sum   = Σ line item amounts
/// total            = max(0, weight_charge + line_items_sum + manual_adjustment)
///
/// Rounding is half-up (matches a phone calculator the rider might run), not
/// banker's rounding. The order is provisional until a final weight is set.
OrderTotal recomputeTotal(PricingInputs inputs) {
  final weightToBill =
      inputs.finalWeightKg ?? inputs.estimatedWeightKg ?? 0;
  final weightCharge = _roundHalfUp(weightToBill * inputs.ratePerKgUgx);
  final lineItemsSum =
      inputs.lineItems.fold<int>(0, (sum, item) => sum + item.amountUgx);
  final raw = weightCharge + lineItemsSum + inputs.manualAdjustmentUgx;
  return OrderTotal(
    weightCharge: weightCharge,
    lineItemsSum: lineItemsSum,
    total: raw < 0 ? 0 : raw,
    isProvisional: inputs.finalWeightKg == null,
  );
}

/// Half-up rounding for non-negative values: (x + 0.5).floor().
int _roundHalfUp(double x) => (x + 0.5).floor();
