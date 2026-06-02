import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/app_database.dart';
import 'supabase_mappers.dart';
import 'supabase_payloads.dart';

/// Read + write repository for customers — ONLINE-ONLY mode.
///
/// Reads stream live from Supabase; writes upsert directly. The offline-first
/// implementation (local Drift reads + outbox-queued writes) is preserved in
/// the commented `OFFLINE` block at the bottom of this file. Mirrors
/// [OrdersRepository]'s shape.
class CustomersRepository {
  CustomersRepository(
    this._supabase, {
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final SupabaseClient _supabase;
  final DateTime Function() _clock;

  Stream<List<Customer>> watchAll() {
    return _supabase
        .from('customers')
        .stream(primaryKey: ['id'])
        .order('name')
        .map((rows) => rows
            .where((r) => r['deleted_at'] == null)
            .map(customerFromSupabase)
            .toList(growable: false));
  }

  Stream<Customer?> watchById(String id) {
    // Filter soft-deleted client-side (same as watchAll) so a back-office
    // tombstone doesn't surface on detail screens. `.stream()` can't express
    // `IS NULL`.
    return _supabase
        .from('customers')
        .stream(primaryKey: ['id'])
        .eq('id', id)
        .map((rows) {
      final live = rows.where((r) => r['deleted_at'] == null);
      return live.isEmpty ? null : customerFromSupabase(live.first);
    });
  }

  /// One-shot fetch of all non-deleted customers. Used by callers that need
  /// the current snapshot without subscribing (e.g. phone-on-blur dedup in
  /// the New Pickup form).
  Future<List<Customer>> getAll() async {
    final rows = await _supabase.from('customers').select().order('name');
    return rows
        .where((r) => r['deleted_at'] == null)
        .map(customerFromSupabase)
        .toList(growable: false);
  }

  Future<void> upsertCustomer(Customer customer) async {
    final now = _clock();
    await _supabase
        .from('customers')
        .upsert(customerUpsertPayload(customer, now: now));
  }
}

/* ============================================================================
 * OFFLINE (Drift local reads + outbox-queued writes) — PRESERVED FOR RE-ENABLE
 * ----------------------------------------------------------------------------
 * import 'package:drift/drift.dart';
 * import '../data/app_database.dart';
 * import 'outbox_repository.dart';
 *
 * class CustomersRepository {
 *   CustomersRepository(this._db, {OutboxRepository? outbox, DateTime Function()? clock})
 *       : _outbox = outbox, _clock = clock ?? DateTime.now;
 *   final AppDatabase _db;
 *   final OutboxRepository? _outbox;
 *   final DateTime Function() _clock;
 *
 *   Stream<List<Customer>> watchAll() {
 *     return (_db.select(_db.customers)
 *           ..where((t) => t.deletedAt.isNull())
 *           ..orderBy([(t) => OrderingTerm(expression: t.name)])).watch();
 *   }
 *
 *   Stream<Customer?> watchById(String id) {
 *     return (_db.select(_db.customers)..where((t) => t.id.equals(id)))
 *         .watchSingleOrNull();
 *   }
 *
 *   Future<List<Customer>> getAll() {
 *     return (_db.select(_db.customers)
 *           ..where((t) => t.deletedAt.isNull())
 *           ..orderBy([(t) => OrderingTerm(expression: t.name)])).get();
 *   }
 *
 *   Future<void> upsertCustomer(Customer customer) async {
 *     final outbox = _requireOutbox();
 *     final now = _clock();
 *     await _db.transaction(() async {
 *       await _db.into(_db.customers).insertOnConflictUpdate(CustomersCompanion(
 *             id: Value(customer.id),
 *             name: Value(customer.name),
 *             phone: Value(customer.phone),
 *             address: Value(customer.address),
 *             notes: Value(customer.notes),
 *             createdAt: Value(customer.createdAt),
 *             updatedAt: Value(now)));
 *       await outbox.enqueue(
 *         id: OutboxRepository.dedupKeyFor(
 *           forTable: 'customers', op: 'insert', rowId: customer.id,
 *           extra: now.toUtc().toIso8601String()),
 *         forTable: 'customers', op: 'insert', rowId: customer.id,
 *         payload: <String, dynamic>{
 *           'id': customer.id, 'name': customer.name, 'phone': customer.phone,
 *           'address': customer.address, 'notes': customer.notes,
 *           'created_at': customer.createdAt.toUtc().toIso8601String(),
 *           'updated_at': now.toUtc().toIso8601String()});
 *     });
 *   }
 *
 *   OutboxRepository _requireOutbox() {
 *     final o = _outbox;
 *     if (o == null) {
 *       throw StateError('CustomersRepository was constructed without an '
 *           'OutboxRepository; upsertCustomer is unavailable.');
 *     }
 *     return o;
 *   }
 * }
 * ========================================================================== */
