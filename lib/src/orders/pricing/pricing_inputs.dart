import 'line_item.dart';

/// Immutable bundle of everything `recomputeTotal` needs. Pure data — no I/O.
class PricingInputs {
  const PricingInputs({
    required this.ratePerKgUgx,
    this.estimatedWeightKg,
    this.finalWeightKg,
    this.lineItems = const [],
    this.manualAdjustmentUgx = 0,
  });

  final double ratePerKgUgx;
  final double? estimatedWeightKg;
  final double? finalWeightKg;
  final List<LineItem> lineItems;
  final int manualAdjustmentUgx;
}

/// Result of `recomputeTotal`: the breakdown plus the clamped total and whether
/// the order is still billing on an estimate.
class OrderTotal {
  const OrderTotal({
    required this.weightCharge,
    required this.lineItemsSum,
    required this.total,
    required this.isProvisional,
  });

  final int weightCharge;
  final int lineItemsSum;
  final int total;
  final bool isProvisional;
}
