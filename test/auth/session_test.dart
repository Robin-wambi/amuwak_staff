import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:amuwak_staff/src/auth/auth_service.dart';
import 'package:amuwak_staff/src/auth/session.dart';

class _MockAuthService extends Mock implements AuthService {}

class _MockUser extends Mock implements User {}

/// Builds an unsigned JWT (header.payload.signature) carrying [claims]. The
/// role reader never verifies the signature, so a dummy segment is fine.
String _token(Map<String, dynamic> claims) {
  String seg(Map<String, dynamic> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  return '${seg({'alg': 'HS256', 'typ': 'JWT'})}.${seg(claims)}.sig';
}

void main() {
  group('roleFromAccessToken', () {
    test('reads the staff role from the user_role claim', () {
      final token = _token({'role': 'authenticated', 'user_role': 'manager'});
      expect(roleFromAccessToken(token), 'manager');
    });

    test('ignores the reserved role claim (PostgREST role switch)', () {
      // The reserved `role` claim is "authenticated" for any signed-in user;
      // it must NOT be mistaken for the staff role.
      final token = _token({'role': 'authenticated'});
      expect(roleFromAccessToken(token), isNull);
    });

    test('returns null for a null token', () {
      expect(roleFromAccessToken(null), isNull);
    });

    test('returns null for a malformed token', () {
      expect(roleFromAccessToken('not-a-jwt'), isNull);
    });

    test('returns null when user_role is present but not a String', () {
      // A misconfigured hook or other issuer could emit a non-String claim;
      // it must degrade to null, not throw a TypeError.
      final token = _token({'user_role': 0});
      expect(roleFromAccessToken(token), isNull);
    });

    test('returns null when the token is expired', () {
      final token = _token({
        'user_role': 'manager',
        'exp': 1000, // 1970 — long past
      });
      expect(roleFromAccessToken(token), isNull);
    });

    test('returns the role when exp is in the future', () {
      final future = DateTime.now().toUtc().add(const Duration(hours: 1));
      final token = _token({
        'user_role': 'in_shop',
        'exp': future.millisecondsSinceEpoch ~/ 1000,
      });
      expect(roleFromAccessToken(token), 'in_shop');
    });

    test('honors a token expired within the clock-skew leeway', () {
      // A device clock slightly ahead of the issuer can put `now` just past
      // `exp`; a few seconds over must not reject an otherwise-valid token.
      final justExpired =
          DateTime.now().toUtc().subtract(const Duration(seconds: 5));
      final token = _token({
        'user_role': 'manager',
        'exp': justExpired.millisecondsSinceEpoch ~/ 1000,
      });
      expect(roleFromAccessToken(token), 'manager');
    });

    test('rejects a token expired beyond the clock-skew leeway', () {
      // 35s past exp is outside the 30s leeway — the token must be rejected.
      final wellExpired =
          DateTime.now().toUtc().subtract(const Duration(seconds: 35));
      final token = _token({
        'user_role': 'manager',
        'exp': wellExpired.millisecondsSinceEpoch ~/ 1000,
      });
      expect(roleFromAccessToken(token), isNull);
    });
  });

  group('currentUserIdProvider', () {
    test(
        'falls back to the restored session before the first auth event '
        'so a returning user is recognised on cold start', () {
      final user = _MockUser();
      when(() => user.id).thenReturn('restored-user');
      final auth = _MockAuthService();
      when(() => auth.currentUser).thenReturn(user);

      final container = ProviderContainer(overrides: [
        authServiceProvider.overrideWithValue(auth),
        // Stream that never emits: authStateProvider stays AsyncLoading, mimicking
        // the cold-start window before supabase emits `initialSession`.
        authStateProvider
            .overrideWith((ref) => const Stream<AuthState>.empty()),
      ]);
      addTearDown(container.dispose);

      expect(container.read(currentUserIdProvider), 'restored-user');
    });

    test('is null when there is no restored session and no event', () {
      final auth = _MockAuthService();
      when(() => auth.currentUser).thenReturn(null);

      final container = ProviderContainer(overrides: [
        authServiceProvider.overrideWithValue(auth),
        authStateProvider
            .overrideWith((ref) => const Stream<AuthState>.empty()),
      ]);
      addTearDown(container.dispose);

      expect(container.read(currentUserIdProvider), isNull);
    });
  });

  group('currentAuthEventProvider', () {
    test('exposes the latest auth lifecycle event from the stream', () async {
      final auth = _MockAuthService();
      final container = ProviderContainer(overrides: [
        authServiceProvider.overrideWithValue(auth),
        authStateProvider.overrideWith(
          (ref) => Stream.value(AuthState(AuthChangeEvent.signedIn, null)),
        ),
      ]);
      addTearDown(container.dispose);

      // Let the StreamProvider resolve its first value before reading.
      await container.read(authStateProvider.future);
      expect(container.read(currentAuthEventProvider),
          AuthChangeEvent.signedIn);
    });

    test('is null before the auth stream has emitted', () {
      final auth = _MockAuthService();
      final container = ProviderContainer(overrides: [
        authServiceProvider.overrideWithValue(auth),
        authStateProvider
            .overrideWith((ref) => const Stream<AuthState>.empty()),
      ]);
      addTearDown(container.dispose);

      expect(container.read(currentAuthEventProvider), isNull);
    });
  });
}
