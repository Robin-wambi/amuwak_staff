import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:amuwak_staff/src/auth/auth_service.dart';
import 'package:amuwak_staff/src/auth/sign_out.dart';
import 'package:amuwak_staff/src/data/app_database.dart';

class _MockAuthService extends Mock implements AuthService {}

class _MockDb extends Mock implements AppDatabase {}

/// Online-only behaviour of [signOutAndReset]. The offline teardown variant is
/// covered by the (skipped) test/sync/sign_out_test.dart, to be restored when
/// offline is re-enabled.
void main() {
  late _MockAuthService auth;

  setUp(() {
    auth = _MockAuthService();
    when(() => auth.signOut()).thenAnswer((_) async {});
  });

  test('revokes the Supabase session via AuthService.signOut', () async {
    await signOutAndReset(auth: auth);

    verify(() => auth.signOut()).called(1);
  });

  test('rejects offline deps in online-only mode (assert guard)', () async {
    // orchestrator/db are ignored online; passing one is a wiring mistake the
    // assert must catch (asserts are enabled under `flutter test`).
    await expectLater(
      signOutAndReset(auth: auth, db: _MockDb()),
      throwsA(isA<AssertionError>()),
    );
  });
}
