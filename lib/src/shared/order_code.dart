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
Future<String> defaultOrderCode() async {
  final result = await Supabase.instance.client.rpc('next_order_code');
  return parseOrderCodeRpcResult(result);
}

/// Normalises whatever `rpc('next_order_code')` decodes to into the code string.
///
/// PostgREST returns a bare scalar for a `RETURNS text` function, so the common
/// case is a plain [String]. We also tolerate the row-set shape
/// (`[{next_order_code: ...}]`) and the single-object shape in case the SDK or
/// PostgREST serialisation differs by version — turning an otherwise cryptic
/// `TypeError` at this network boundary into a clear, diagnosable failure.
///
/// An empty/blank result is rejected too: it can't be a real code, would render
/// as a blank order reference, and is almost certainly a server-side fault we'd
/// rather surface loudly than silently persist. We deliberately do NOT enforce
/// the full `AMW-YYYY-NNNN` shape here — that would brittly couple this boundary
/// to the server's format and reject a legitimately-evolved code.
String parseOrderCodeRpcResult(Object? result) {
  if (result is String) {
    if (result.trim().isEmpty) {
      throw StateError('next_order_code RPC returned an empty code');
    }
    return result;
  }
  if (result is List && result.isNotEmpty) {
    return parseOrderCodeRpcResult(result.first);
  }
  if (result is Map && result.values.isNotEmpty) {
    // Prefer the named column so a multi-column row can't return the wrong
    // value off whichever key happens to come first; fall back to the sole
    // value for the canonical single-column shape.
    final keyed = result['next_order_code'];
    return parseOrderCodeRpcResult(keyed ?? result.values.first);
  }
  throw StateError('next_order_code RPC returned an unexpected shape: $result');
}
