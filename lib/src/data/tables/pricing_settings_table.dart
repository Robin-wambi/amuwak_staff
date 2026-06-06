import 'package:drift/drift.dart';

class PricingSettings extends Table {
  TextColumn     get id                   => text()();
  RealColumn     get defaultRatePerKgUgx  => real().named('default_rate_per_kg_ugx')();
  DateTimeColumn get updatedAt            => dateTime().named('updated_at')();
  TextColumn     get updatedBy            => text().named('updated_by').nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
