import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_service.dart';

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(authServiceProvider).authStateChanges;
});

final currentUserIdProvider = Provider<String?>((ref) {
  return ref.watch(authStateProvider).valueOrNull?.session?.user.id;
});

/// The staff role is injected by the custom_access_token_hook (Supabase
/// migration 0009, fixed in 0025) under the `user_role` claim. It must NOT use
/// the reserved `role` claim: PostgREST reads `role` to pick the Postgres role
/// for each request (`SET ROLE`), so overwriting it with a staff role like
/// 'manager' — which is not a real Postgres role — makes every data request
/// fail. Read the staff role from `user_role` instead.
///
/// Returns null if the token is missing, malformed, already expired, or has no
/// `user_role` claim. The `exp` check guards against the narrow window where a
/// background token refresh has rotated the JWT but `authStateProvider` has not
/// yet emitted — without it we'd serve a stale role from the dead token until
/// the StreamProvider catches up.
String? roleFromAccessToken(String? token) {
  if (token == null) return null;
  final parts = token.split('.');
  if (parts.length != 3) return null;
  final padded = parts[1] + '=' * ((4 - parts[1].length % 4) % 4);
  final Map<String, dynamic> payload;
  try {
    payload = jsonDecode(utf8.decode(base64Url.decode(padded)))
        as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
  final exp = payload['exp'];
  if (exp is int) {
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true);
    if (DateTime.now().toUtc().isAfter(expiresAt)) return null;
  }
  return payload['user_role'] as String?;
}

final currentRoleProvider = Provider<String?>((ref) {
  final token = ref.watch(authStateProvider).valueOrNull?.session?.accessToken;
  return roleFromAccessToken(token);
});
