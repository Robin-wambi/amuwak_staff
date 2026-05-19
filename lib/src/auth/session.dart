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
final currentRoleProvider = Provider<String?>((ref) {
  final token = ref.watch(authStateProvider).valueOrNull?.session?.accessToken;
  if (token == null) return null;
  final parts = token.split('.');
  if (parts.length != 3) return null;
  final padded = parts[1] + '=' * ((4 - parts[1].length % 4) % 4);
  final payload =
      jsonDecode(utf8.decode(base64Url.decode(padded))) as Map<String, dynamic>;
  return payload['role'] as String?;
});
