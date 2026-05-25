/// User-facing service categories. The `.label` returns the human display
/// string; `.toDbString` returns the value persisted to `orders.service_type`
/// in Drift + Supabase.
///
/// `.label` and `.toDbString` happen to produce the same string today.
/// Kept distinct because the human label and the persisted form will diverge
/// if Amuwak ever localizes the UI or migrates the DB to a normalized code
/// (e.g. `'wash_iron'`).
enum ServiceType {
  washAndIron,
  dryCleaning,
  ironOnly,
  washOnly;

  String get label => switch (this) {
    ServiceType.washAndIron => 'Wash & Iron',
    ServiceType.dryCleaning => 'Dry cleaning',
    ServiceType.ironOnly    => 'Iron only',
    ServiceType.washOnly    => 'Wash only',
  };

  String toDbString() => switch (this) {
    ServiceType.washAndIron => 'Wash & Iron',
    ServiceType.dryCleaning => 'Dry cleaning',
    ServiceType.ironOnly    => 'Iron only',
    ServiceType.washOnly    => 'Wash only',
  };

  static ServiceType fromDbString(String s) => switch (s) {
    'Wash & Iron'  => ServiceType.washAndIron,
    'Dry cleaning' => ServiceType.dryCleaning,
    'Iron only'    => ServiceType.ironOnly,
    'Wash only'    => ServiceType.washOnly,
    _ => throw ArgumentError.value(s, 'serviceType', 'unknown service type'),
  };
}
