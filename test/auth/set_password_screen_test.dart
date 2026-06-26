import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:amuwak_staff/src/auth/auth_service.dart';
import 'package:amuwak_staff/src/auth/session.dart';
import 'package:amuwak_staff/src/auth/set_password_screen.dart';

class _MockAuthService extends Mock implements AuthService {}

Future<void> _pump(
  WidgetTester tester, {
  required AuthService authService,
  required VoidCallback onCompleted,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [authServiceProvider.overrideWithValue(authService)],
      child: MaterialApp(
        home: SetPasswordScreen(onCompleted: onCompleted),
      ),
    ),
  );
}

void main() {
  late _MockAuthService auth;

  setUp(() {
    auth = _MockAuthService();
  });

  Future<void> enterBoth(WidgetTester tester, String pw, String confirm) async {
    await tester.enterText(
        find.widgetWithText(TextFormField, 'New password'), pw);
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirm password'), confirm);
  }

  testWidgets('mismatched passwords show an error and do not save',
      (tester) async {
    var completed = false;
    await _pump(tester, authService: auth, onCompleted: () => completed = true);

    await enterBoth(tester, 'longenough1', 'different1');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save password'));
    await tester.pump();

    expect(find.text('Passwords do not match'), findsOneWidget);
    verifyNever(() => auth.updatePassword(any()));
    expect(completed, isFalse);
  });

  testWidgets('too-short password shows an error and does not save',
      (tester) async {
    await _pump(tester, authService: auth, onCompleted: () {});

    await enterBoth(tester, 'short', 'short');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save password'));
    await tester.pump();

    expect(find.text('At least 8 characters'), findsOneWidget);
    verifyNever(() => auth.updatePassword(any()));
  });

  testWidgets('valid password calls updatePassword then onCompleted',
      (tester) async {
    when(() => auth.updatePassword(any())).thenAnswer((_) async {});
    var completed = false;
    await _pump(tester, authService: auth, onCompleted: () => completed = true);

    await enterBoth(tester, 'longenough1', 'longenough1');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save password'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    verify(() => auth.updatePassword('longenough1')).called(1);
    expect(completed, isTrue);
  });

  testWidgets('AuthFailure shows the message and does not complete',
      (tester) async {
    when(() => auth.updatePassword(any()))
        .thenThrow(AuthFailure('Password is too weak'));
    var completed = false;
    await _pump(tester, authService: auth, onCompleted: () => completed = true);

    await enterBoth(tester, 'longenough1', 'longenough1');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save password'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Password is too weak'), findsOneWidget);
    expect(completed, isFalse);
  });
}
