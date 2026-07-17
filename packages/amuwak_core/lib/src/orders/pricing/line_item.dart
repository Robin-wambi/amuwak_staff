/// A free-form charge for a special piece (blanket, jacket, duvet…) on an order.
/// `name` is trimmed and must be non-empty; `amountUgx` is integer UGX >= 0.
/// Discounts do NOT go here — they go through the order's manual adjustment.
class LineItem {
  LineItem({required String name, required this.amountUgx})
      : name = name.trim() {
    if (this.name.isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be empty');
    }
    if (amountUgx < 0) {
      throw ArgumentError.value(amountUgx, 'amountUgx', 'must be >= 0');
    }
  }

  final String name;
  final int amountUgx;

  /// Serializes to the snake_case shape stored in `orders.line_items` (jsonb).
  Map<String, dynamic> toJson() => {'name': name, 'amount_ugx': amountUgx};

  /// Reads either a freshly-decoded jsonb map (Supabase) or a `toJson` map.
  factory LineItem.fromJson(Map<String, dynamic> json) => LineItem(
        name: json['name'] as String,
        amountUgx: (json['amount_ugx'] as num).toInt(),
      );

  @override
  bool operator ==(Object other) =>
      other is LineItem && other.name == name && other.amountUgx == amountUgx;

  @override
  int get hashCode => Object.hash(name, amountUgx);

  @override
  String toString() => 'LineItem($name, $amountUgx)';
}
