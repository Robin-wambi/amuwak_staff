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
  return result as String;
}
