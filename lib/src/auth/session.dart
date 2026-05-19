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

/// The `role` claim is injected by the custom_access_token_hook in Supabase
/// migration 0009. Read it from the access-token JWT payload.
///
/// Returns null if the token is missing, malformed, or already expired.
/// The `exp` check guards against the narrow window where a background
/// token refresh has rotated the JWT but `authStateProvider` has not yet
/// emitted — without it we'd serve a stale `role` from the dead token
/// until the StreamProvider catches up.
final currentRoleProvider = Provider<String?>((ref) {
  final token = ref.watch(authStateProvider).valueOrNull?.session?.accessToken;
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
  return payload['role'] as String?;
});
