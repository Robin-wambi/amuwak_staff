import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:amuwak_staff/src/auth/auth_service.dart';

class _MockGoTrue extends Mock implements GoTrueClient {}

class _FakeAuthResponse extends Fake implements AuthResponse {}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeAuthResponse());
  });

  group('AuthService.signInWithUsernamePin', () {
    late _MockGoTrue goTrue;
    late AuthService service;

    setUp(() {
      goTrue = _MockGoTrue();
      service = AuthService(goTrue: goTrue);
    });

    test('composes the synthetic email from the username', () async {
      when(() => goTrue.signInWithPassword(
            email: any(named: 'email'),
            password: any(named: 'password'),
          )).thenAnswer((_) async => _FakeAuthResponse());

      await service.signInWithUsernamePin(username: 'John', pin: '123456');

      verify(() => goTrue.signInWithPassword(
            email: 'john@amuwak.local',
            password: '123456',
          )).called(1);
    });

    test('throws AuthFailure when Supabase raises AuthException', () async {
      when(() => goTrue.signInWithPassword(
            email: any(named: 'email'),
            password: any(named: 'password'),
          )).thenThrow(const AuthException('Invalid login credentials'));

      expect(
        () => service.signInWithUsernamePin(username: 'john', pin: 'wrong'),
        throwsA(isA<AuthFailure>().having(
          (e) => e.message,
          'message',
          contains('Invalid'),
        )),
      );
    });
  });
}
