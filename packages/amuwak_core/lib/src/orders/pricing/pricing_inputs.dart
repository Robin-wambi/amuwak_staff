import 'line_item.dart';

/// Immutable bundle of everything `recomputeTotal` needs. Pure data — no I/O.
class PricingInputs {
  const PricingInputs({
    required this.ratePerKgUgx,
    this.estimatedWeightKg,
    this.finalWeightKg,
    this.lineItems = const [],
    this.manualAdjustmentUgx = 0,
    this.deliveryFeeUgx = 0,
    this.isExpress = false,
    this.expressFlatUgx = 0,
    this.expressPct = 0,
  });

  final double ratePerKgUgx;
  final double? estimatedWeightKg;
  final double? finalWeightKg;
  final List<LineItem> lineItems;
  final int manualAdjustmentUgx;

  /// Flat delivery fee added to the total. 0 when the order has no delivery.
  final int deliveryFeeUgx;

  /// Whether the express/turnaround surcharge applies to this order.
  final bool isExpress;

  /// Flat express add-on (UGX), applied when [isExpress]. The frozen
  /// `express_flat_snapshot_ugx` from the order in production.
  final int expressFlatUgx;

  /// Express percentage uplift, applied when [isExpress], on the weight charge
  /// plus line items (not delivery or manual adjustment). e.g. 30 == 30%.
  final double expressPct;
}

/// Result of `recomputeTotal`: the breakdown plus the clamped total and whether
/// the order is still billing on an estimate.
class OrderTotal {
  const OrderTotal({
    required this.weightCharge,
    required this.lineItemsSum,
    required this.expressSurcharge,
    required this.deliveryFee,
    required this.total,
    required this.isProvisional,
  });

  final int weightCharge;
  final int lineItemsSum;
  final int expressSurcharge;
  final int deliveryFee;
  final int total;
  final bool isProvisional;
}
