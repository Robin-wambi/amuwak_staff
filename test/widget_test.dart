import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:amuwak_staff/main.dart';
import 'package:amuwak_staff/src/sync/sync_orchestrator_provider.dart';

void main() {
  // syncLifecycleProvider would otherwise pull in syncOrchestratorProvider,
  // which builds a real SyncOrchestrator against Supabase.instance.client —
  // not safe in widget tests. Override it with a no-op so the lifecycle
  // listener is silently absent.
  final lifecycleNoop = <Override>[
    syncLifecycleProvider.overrideWith((ref) {}),
  ];

  testWidgets('App opens to login screen first', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: lifecycleNoop,
        child: const AmuwakStaffApp(),
      ),
    );

    // The login subtitle is unique to the login screen, so use it as the anchor.
    expect(find.text('Login to manage laundry orders'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Login'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2));
  });

  // Form validation, the success path, and the failure path are covered by
  // test/auth/login_screen_test.dart. This file is now scoped to the
  // bootstrap path only (the test above), which AmuwakStaffApp's
  // syncLifecycleProvider override is wired for.
}
