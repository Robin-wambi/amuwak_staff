/// The singleton global pricing configuration (one row in `pricing_settings`).
/// `defaultRatePerKgUgx` is the rate used for any customer without an override.
class PricingSettings {
  const PricingSettings({
    required this.id,
    required this.defaultRatePerKgUgx,
    required this.updatedAt,
    this.updatedBy,
  });

  final String id;
  final double defaultRatePerKgUgx;
  final DateTime updatedAt;
  final String? updatedBy;

  factory PricingSettings.fromSupabase(Map<String, dynamic> r) =>
      PricingSettings(
        id: r['id'] as String,
        defaultRatePerKgUgx:
            (r['default_rate_per_kg_ugx'] as num).toDouble(),
        updatedAt: DateTime.parse(r['updated_at'] as String),
        updatedBy: r['updated_by'] as String?,
      );
}
