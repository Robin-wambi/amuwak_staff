import '../data/app_database.dart' show Customer;
import '../orders/order.dart';
import '../orders/order_status.dart';
import '../orders/proof_event.dart';

/// Pure builders for the ONLINE write path: domain model → snake_case Supabase
/// row map. The counterparts to the read mappers in `supabase_mappers.dart`.
///
/// Extracted from the repositories so the payload shapes (column names, casing,
/// UTC ISO timestamps) are unit-testable without mocking the Supabase client.
/// Keep the keys in sync with the table definitions under `lib/src/data/tables/`.
///
/// `app_database.dart` is imported `show Customer` so the Drift `ProofEvent`
/// row class doesn't collide with the domain [ProofEvent] used here.

Map<String, dynamic> orderUpsertPayload(
  LaundryOrder order, {
  required String actorStaffId,
  required DateTime now,
}) =>
    {
      'id': order.orderId,
      'order_code': order.orderCode,
      'customer_id': order.customerId,
      'customer_name': order.customerName,
      'phone': order.phone,
      'address': order.address,
      'service_type': order.serviceType.toDbString(),
      'status': order.status.toDbString(),
      'intake_method': order.intakeMethod,
      'fulfillment_method': order.fulfillmentMethod,
      'item_count': order.itemCount,
      'notes': order.notes,
      'scheduled_for': order.scheduledFor?.toUtc().toIso8601String(),
      'intake_recorded_by': actorStaffId,
      'created_by': actorStaffId,
      'created_at': now.toUtc().toIso8601String(),
      'updated_at': now.toUtc().toIso8601String(),
    };

Map<String, dynamic> orderStatusUpdatePayload(
  OrderStatus status, {
  required DateTime now,
}) =>
    {
      'status': status.toDbString(),
      'updated_at': now.toUtc().toIso8601String(),
    };

Map<String, dynamic> customerUpsertPayload(
  Customer customer, {
  required DateTime now,
}) =>
    {
      'id': customer.id,
      'name': customer.name,
      'phone': customer.phone,
      'address': customer.address,
      'notes': customer.notes,
      'created_at': customer.createdAt.toUtc().toIso8601String(),
      'updated_at': now.toUtc().toIso8601String(),
    };

Map<String, dynamic> proofEventUpsertPayload(
  ProofEvent event, {
  required String orderId,
  required String actorStaffId,
  required DateTime now,
}) =>
    {
      'id': event.id,
      'order_id': orderId,
      'type': event.type.name,
      'captured_at': event.capturedAt.toUtc().toIso8601String(),
      'item_count': event.count,
      'notes': event.notes,
      'captured_by': actorStaffId,
      'created_at': now.toUtc().toIso8601String(),
      'updated_at': now.toUtc().toIso8601String(),
    };
