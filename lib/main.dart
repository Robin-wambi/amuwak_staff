import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'src/auth/login_screen.dart';
import 'src/bootstrap/app_bootstrap.dart';
import 'src/printing/printing_providers.dart';
import 'src/shared/widgets/app_theme.dart';
// ONLINE-ONLY: the sync orchestrator (offline engine) is disabled. Re-add this
// import and the `ref.watch(syncLifecycleProvider)` below to restore offline.
// import 'src/sync/sync_orchestrator_provider.dart';

Future<void> main() async {
  await AppBootstrap.initialize();
  // Resolved once here so screens can read PrinterStore synchronously.
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const AmuwakStaffApp(),
    ),
  );
}

class AmuwakStaffApp extends ConsumerWidget {
  const AmuwakStaffApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ONLINE-ONLY: offline sync engine disabled. Previously this eagerly
    // resolved `syncLifecycleProvider` so its auth-state listener started the
    // SyncOrchestrator on sign-in. Re-enable to restore offline:
    //   ref.watch(syncLifecycleProvider);

    return MaterialApp(
      title: 'Amuwak Staff',
      debugShowCheckedModeBanner: false,
      theme: buildAmuwakTheme(),
      home: const LoginScreen(),
    );
  }
}
