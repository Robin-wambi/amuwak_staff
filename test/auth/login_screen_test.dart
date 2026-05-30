import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:amuwak_staff/src/auth/auth_service.dart';
import 'package:amuwak_staff/src/auth/login_screen.dart';
import 'package:amuwak_staff/src/auth/session.dart';
import 'package:amuwak_staff/src/dashboard/staff_dashboard_screen.dart';
import 'package:amuwak_staff/src/orders/order.dart';
import 'package:amuwak_staff/src/sync/repository_providers.dart';
import 'package:amuwak_staff/src/sync/sync_orchestrator_provider.dart';
import 'package:amuwak_staff/src/sync/sync_status.dart';

class _MockAuthService extends Mock implements AuthService {}

Future<void> _pumpLogin(
  WidgetTester tester, {
  required AuthService authService,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authServiceProvider.overrideWithValue(authService),
        // Stub sync-side providers so the dashboard (post-login navigation
        // target) builds without touching Supabase or Drift streams.
        syncLifecycleProvider.overrideWith((ref) {}),
        // Emit ONE value (empty list) immediately so the dashboard's
        // ordersAsync.when() resolves to the data branch — its loading
        // branch shows a LinearProgressIndicator which would make
        // pumpAndSettle hang forever in this test.
        ordersStreamProvider.overrideWith(
            (ref) => Stream<List<LaundryOrder>>.value(const [])),
        pendingOutboxCountProvider
            .overrideWith((ref) => const Stream<int>.empty()),
        lastSyncedAtProvider
            .overrideWith((ref) => const Stream<DateTime?>.empty()),
      ],
      child: const MaterialApp(home: LoginScreen()),
    ),
  );
}

void main() {
  late _MockAuthService auth;

  setUp(() {
    auth = _MockAuthService();
  });

  testWidgets('empty fields show validation messages on tap', (tester) async {
    await _pumpLogin(tester, authService: auth);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Login'));
    await tester.pump();

    expect(find.text('Enter your username'), findsOneWidget);
    expect(find.text('Enter your PIN'), findsOneWidget);
    verifyNever(() => auth.signInWithUsernamePin(
        username: any(named: 'username'), pin: any(named: 'pin')));
  });

  testWidgets('successful login pushes the dashboard', (tester) async {
    when(() => auth.signInWithUsernamePin(
        username: 'rider1', pin: '1234')).thenAnswer((_) async {});

    await _pumpLogin(tester, authService: auth);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Username'),
      'rider1',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'PIN'),
      '1234',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Login'));
    await tester.pumpAndSettle();

    expect(find.byType(StaffDashboardScreen), findsOneWidget);
  });

  testWidgets('AuthFailure shows the error message and stays on login',
      (tester) async {
    when(() => auth.signInWithUsernamePin(
        username: 'rider1',
        pin: '0000')).thenThrow(AuthFailure('Invalid username or PIN'));

    await _pumpLogin(tester, authService: auth);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Username'),
      'rider1',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'PIN'),
      '0000',
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Login'));
    await tester.pump();

    expect(find.text('Invalid username or PIN'), findsOneWidget);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(StaffDashboardScreen), findsNothing);
  });
}
