import 'package:supabase_flutter/supabase_flutter.dart';

/// Reserves the next human-facing order code (e.g. `AMW-2026-0042`) from the
/// server. Backed by the `next_order_code()` Postgres function, which atomically
/// bumps a per-year counter — so codes are sequential and never collide across
/// devices, even though several riders may create orders at once.
///
/// Used as the production tear-off for [NewPickupScreen.orderCodeGenerator];
/// tests inject a deterministic stand-in instead. Requires connectivity at
/// order-creation time: the RPC throws when offline, which the form surfaces as
/// a retryable error.
Future<String> defaultOrderCode([SupabaseClient? client]) async {
  final c = client ?? Supabase.instance.client;
  final result = await c.rpc('next_order_code');
  return parseOrderCodeRpcResult(result);
}

/// Normalises whatever `rpc('next_order_code')` decodes to into the code string.
///
/// PostgREST returns a bare scalar for a `RETURNS text` function, so the common
/// case is a plain [String]. We also tolerate the row-set shape
/// (`[{next_order_code: ...}]`) and the single-object shape in case the SDK or
/// PostgREST serialisation differs by version — turning an otherwise cryptic
/// `TypeError` at this network boundary into a clear, diagnosable failure.
String parseOrderCodeRpcResult(Object? result) {
  if (result is String) return result;
  if (result is List && result.isNotEmpty) {
    return parseOrderCodeRpcResult(result.first);
  }
  if (result is Map && result.values.isNotEmpty) {
    final value = result.values.first;
    if (value is String) return value;
  }
  throw StateError('next_order_code RPC returned an unexpected shape: $result');
}
