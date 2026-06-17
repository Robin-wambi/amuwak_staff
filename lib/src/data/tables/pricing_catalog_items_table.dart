import 'package:drift/drift.dart';

/// Managed catalog of priced service items staff pick from at billing. Retired
/// items keep `active = false` (hidden from the picker, preserved for history).
class PricingCatalogItems extends Table {
  TextColumn     get id        => text()();
  TextColumn     get name      => text()();
  IntColumn      get amountUgx => integer().named('amount_ugx')();
  BoolColumn     get active    => boolean().withDefault(const Constant(true))();
  IntColumn      get sortOrder => integer().named('sort_order').withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}
