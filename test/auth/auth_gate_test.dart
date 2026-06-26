import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:amuwak_staff/src/auth/auth_gate.dart';
import 'package:amuwak_staff/src/auth/auth_service.dart';
import 'package:amuwak_staff/src/auth/login_screen.dart';
import 'package:amuwak_staff/src/auth/session.dart';
import 'package:amuwak_staff/src/auth/set_password_screen.dart';
import 'package:amuwak_staff/src/dashboard/current_staff_provider.dart';
import 'package:amuwak_staff/src/dashboard/staff_dashboard_screen.dart';
import 'package:amuwak_staff/src/data/app_database.dart';
import 'package:amuwak_staff/src/orders/order.dart';
import 'package:amuwak_staff/src/sync/repository_providers.dart';

class _MockAuthService extends Mock implements AuthService {}

/// Controllable event source so a test can change the auth event mid-render.
final _testEventProvider =
    StateProvider<AuthChangeEvent?>((_) => AuthChangeEvent.passwordRecovery);

/// Controllable signed-in user id so a test can simulate sign-out mid-render.
final _testUserIdProvider = StateProvider<String?>((_) => 'u1');

/// Overrides that let the heavy dashboard build without touching Supabase.
List<Override> _dashboardStubs() => [
      currentRoleProvider.overrideWithValue(null),
      currentStaffProvider.overrideWith((ref) => Stream<StaffData?>.value(null)),
      ordersStreamProvider
          .overrideWith((ref) => Stream<List<LaundryOrder>>.value(const [])),
    ];

Future<void> _pumpGate(
  WidgetTester tester, {
  required List<Override> overrides,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: const MaterialApp(home: AuthGate()),
    ),
  );
}

void main() {
  testWidgets('shows LoginScreen when nobody is signed in', (tester) async {
    await _pumpGate(tester, overrides: [
      currentUserIdProvider.overrideWithValue(null),
      lastAuthEventProvider.overrideWithValue(null),
    ]);

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(StaffDashboardScreen), findsNothing);
  });

  testWidgets('shows SetPasswordScreen after a passwordRecovery event',
      (tester) async {
    await _pumpGate(tester, overrides: [
      currentUserIdProvider.overrideWithValue('u1'),
      lastAuthEventProvider
          .overrideWithValue(AuthChangeEvent.passwordRecovery),
      authServiceProvider.overrideWithValue(_MockAuthService()),
    ]);

    expect(find.byType(SetPasswordScreen), findsOneWidget);
    expect(find.byType(StaffDashboardScreen), findsNothing);
  });

  testWidgets('shows the dashboard when signed in normally', (tester) async {
    await _pumpGate(tester, overrides: [
      currentUserIdProvider.overrideWithValue('u1'),
      lastAuthEventProvider.overrideWithValue(AuthChangeEvent.signedIn),
      authServiceProvider.overrideWithValue(_MockAuthService()),
      ..._dashboardStubs(),
    ]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(StaffDashboardScreen), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
  });

  testWidgets('leaves SetPassword for the dashboard once the password is set',
      (tester) async {
    final auth = _MockAuthService();
    when(() => auth.updatePassword(any())).thenAnswer((_) async {});

    await _pumpGate(tester, overrides: [
      currentUserIdProvider.overrideWithValue('u1'),
      lastAuthEventProvider
          .overrideWithValue(AuthChangeEvent.passwordRecovery),
      authServiceProvider.overrideWithValue(auth),
      ..._dashboardStubs(),
    ]);

    expect(find.byType(SetPasswordScreen), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextFormField, 'New password'), 'longenough1');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirm password'), 'longenough1');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save password'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(SetPasswordScreen), findsNothing);
    expect(find.byType(StaffDashboardScreen), findsOneWidget);
  });

  testWidgets(
      'a token refresh during recovery keeps the user on SetPassword',
      (tester) async {
    final container = ProviderContainer(overrides: [
      currentUserIdProvider.overrideWithValue('u1'),
      lastAuthEventProvider.overrideWith((ref) => ref.watch(_testEventProvider)),
      authServiceProvider.overrideWithValue(_MockAuthService()),
      ..._dashboardStubs(),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: AuthGate()),
    ));

    expect(find.byType(SetPasswordScreen), findsOneWidget);

    // Supabase can fire tokenRefreshed during the recovery window; the sticky
    // _recovering flag must keep the user on the password form, not route them
    // to the dashboard.
    container.read(_testEventProvider.notifier).state =
        AuthChangeEvent.tokenRefreshed;
    await tester.pump();

    expect(find.byType(SetPasswordScreen), findsOneWidget);
    expect(find.byType(StaffDashboardScreen), findsNothing);
  });

  testWidgets('routes back to LoginScreen when the session ends (sign-out)',
      (tester) async {
    final container = ProviderContainer(overrides: [
      currentUserIdProvider.overrideWith((ref) => ref.watch(_testUserIdProvider)),
      lastAuthEventProvider.overrideWithValue(AuthChangeEvent.signedIn),
      authServiceProvider.overrideWithValue(_MockAuthService()),
      ..._dashboardStubs(),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: AuthGate()),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(StaffDashboardScreen), findsOneWidget);

    // Sign out: the session id clears. AuthGate must show the login screen so a
    // subsequent sign-in routes forward again (the dashboard no longer does this
    // itself).
    container.read(_testUserIdProvider.notifier).state = null;
    await tester.pump();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(StaffDashboardScreen), findsNothing);
  });
}
