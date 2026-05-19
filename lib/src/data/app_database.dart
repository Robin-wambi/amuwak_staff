import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tables/staff_table.dart';
import 'tables/customers_table.dart';
import 'tables/orders_table.dart';
import 'tables/order_status_events_table.dart';
import 'tables/proof_events_table.dart';
import 'tables/proof_photos_table.dart';
import 'tables/issues_table.dart';
import 'tables/shifts_table.dart';
import 'tables/valid_transitions_table.dart';
import 'tables/outbox_table.dart';
import 'tables/sync_watermarks_table.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [
  Staff, Customers, Orders, OrderStatusEvents,
  ProofEvents, ProofPhotos, Issues, Shifts,
  ValidTransitions, Outbox, SyncWatermarks,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());
  AppDatabase.forTesting(QueryExecutor e) : super(e);

  @override
  int get schemaVersion => 1;
}

LazyDatabase _openConnection() => LazyDatabase(() async {
  final dbFolder = await getApplicationDocumentsDirectory();
  final file = File(p.join(dbFolder.path, 'amuwak_staff.db'));
  return NativeDatabase.createInBackground(file);
});
