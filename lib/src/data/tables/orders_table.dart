import 'package:drift/drift.dart';

class Orders extends Table {
  TextColumn     get id                 => text()();
  TextColumn     get orderCode          => text().named('order_code')();
  TextColumn     get customerId         => text().named('customer_id').nullable()();
  TextColumn     get customerName       => text().named('customer_name')();
  TextColumn     get phone              => text()();
  TextColumn     get address            => text()();
  TextColumn     get serviceType        => text().named('service_type')();
  TextColumn     get status             => text()();
  TextColumn     get intakeMethod       => text().named('intake_method')();
  TextColumn     get fulfillmentMethod  => text().named('fulfillment_method')();
  IntColumn      get itemCount          => integer().named('item_count')();
  TextColumn     get notes              => text().withDefault(const Constant(''))();
  DateTimeColumn get scheduledFor       => dateTime().named('scheduled_for').nullable()();
  TextColumn     get assignedDriver     => text().named('assigned_driver').nullable()();
  TextColumn     get intakeRecordedBy   => text().named('intake_recorded_by')();
  TextColumn     get createdBy          => text().named('created_by')();
  DateTimeColumn get createdAt          => dateTime().named('created_at').withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt          => dateTime().named('updated_at').withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt          => dateTime().named('deleted_at').nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
