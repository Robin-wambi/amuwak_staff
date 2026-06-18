/// A managed, priced service item staff can pick at billing (blanket, duvet,
/// jacket…). Picking one appends an ordinary `LineItem` to the order — the
/// catalog is the source of suggestions, not a per-order structure.
///
/// `name` is trimmed and must be non-empty; `amountUgx` is integer UGX >= 0.
/// `active` is false for retired items (kept for history, hidden from the
/// picker). `sortOrder` controls display order (lower first).
class CatalogItem {
  CatalogItem({
    required this.id,
    required String name,
    required this.amountUgx,
    this.active = true,
    this.sortOrder = 0,
  }) : name = name.trim() {
    if (this.name.isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be empty');
    }
    if (amountUgx < 0) {
      throw ArgumentError.value(amountUgx, 'amountUgx', 'must be >= 0');
    }
  }

  final String id;
  final String name;
  final int amountUgx;
  final bool active;
  final int sortOrder;

  /// Reads a Supabase `pricing_catalog_items` row. `active`/`sort_order` degrade
  /// to their defaults if absent.
  factory CatalogItem.fromSupabase(Map<String, dynamic> r) => CatalogItem(
        id: r['id'] as String,
        name: r['name'] as String,
        amountUgx: (r['amount_ugx'] as num).toInt(),
        active: (r['active'] as bool?) ?? true,
        sortOrder: (r['sort_order'] as num?)?.toInt() ?? 0,
      );

  /// The snake_case shape written to `pricing_catalog_items`.
  Map<String, dynamic> toSupabase() => {
        'id': id,
        'name': name,
        'amount_ugx': amountUgx,
        'active': active,
        'sort_order': sortOrder,
      };

  CatalogItem copyWith({
    String? name,
    int? amountUgx,
    bool? active,
    int? sortOrder,
  }) =>
      CatalogItem(
        id: id,
        name: name ?? this.name,
        amountUgx: amountUgx ?? this.amountUgx,
        active: active ?? this.active,
        sortOrder: sortOrder ?? this.sortOrder,
      );

  @override
  bool operator ==(Object other) =>
      other is CatalogItem &&
      other.id == id &&
      other.name == name &&
      other.amountUgx == amountUgx &&
      other.active == active &&
      other.sortOrder == sortOrder;

  @override
  int get hashCode => Object.hash(id, name, amountUgx, active, sortOrder);

  @override
  String toString() =>
      'CatalogItem($id, $name, $amountUgx, active: $active, sort: $sortOrder)';
}
