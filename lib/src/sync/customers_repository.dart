import 'package:drift/drift.dart';

import '../data/app_database.dart';
import 'outbox_repository.dart';

/// Read + write repository for customers.
///
/// Write methods ([upsertCustomer]) require an [OutboxRepository] to be
/// supplied at construction time. Callers that only need the read API can
/// omit it; attempting a write on a read-only-configured instance throws a
/// [StateError]. Mirrors [OrdersRepository]'s shape.
class CustomersRepository {
  CustomersRepository(
    this._db, {
    OutboxRepository? outbox,
    DateTime Function()? clock,
  })  : _outbox = outbox,
        _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final OutboxRepository? _outbox;
  final DateTime Function() _clock;

  Stream<List<Customer>> watchAll() {
    return (_db.select(_db.customers)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm(expression: t.name)]))
        .watch();
  }

  Stream<Customer?> watchById(String id) {
    return (_db.select(_db.customers)..where((t) => t.id.equals(id)))
        .watchSingleOrNull();
  }

  /// One-shot fetch of all non-deleted customers. Used by callers that need
  /// the current snapshot without subscribing (e.g. phone-on-blur dedup in
  /// the New Pickup form).
  Future<List<Customer>> getAll() {
    return (_db.select(_db.customers)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm(expression: t.name)]))
        .get();
  }

  Future<void> upsertCustomer(Customer customer) async {
    final outbox = _requireOutbox();
    final now = _clock();
    await _db.transaction(() async {
      await _db.into(_db.customers).insertOnConflictUpdate(
            CustomersCompanion(
              id: Value(customer.id),
              name: Value(customer.name),
              phone: Value(customer.phone),
              address: Value(customer.address),
              notes: Value(customer.notes),
              createdAt: Value(customer.createdAt),
              updatedAt: Value(now),
            ),
          );
      await outbox.enqueue(
        id: OutboxRepository.dedupKeyFor(
          forTable: 'customers',
          op: 'insert',
          rowId: customer.id,
          extra: now.toUtc().toIso8601String(),
        ),
        forTable: 'customers',
        op: 'insert',
        rowId: customer.id,
        payload: <String, dynamic>{
          'id': customer.id,
          'name': customer.name,
          'phone': customer.phone,
          'address': customer.address,
          'notes': customer.notes,
          'created_at': customer.createdAt.toUtc().toIso8601String(),
          'updated_at': now.toUtc().toIso8601String(),
        },
      );
    });
  }

  OutboxRepository _requireOutbox() {
    final o = _outbox;
    if (o == null) {
      throw StateError(
        'CustomersRepository was constructed without an OutboxRepository; '
        'upsertCustomer is unavailable.',
      );
    }
    return o;
  }
}
