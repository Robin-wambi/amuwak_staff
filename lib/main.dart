import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'src/auth/login_screen.dart';
import 'src/bootstrap/app_bootstrap.dart';
import 'src/shared/widgets/app_theme.dart';
import 'src/sync/sync_orchestrator_provider.dart';

Future<void> main() async {
  await AppBootstrap.initialize();
  runApp(const ProviderScope(child: AmuwakStaffApp()));
}

class AmuwakStaffApp extends ConsumerWidget {
  const AmuwakStaffApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Eagerly resolve the sync lifecycle so its auth-state listener
    // installs as soon as the app mounts. Without this watch, the
    // listener never fires and the SyncOrchestrator never starts.
    ref.watch(syncLifecycleProvider);

    return MaterialApp(
      title: 'Amuwak Staff',
      debugShowCheckedModeBanner: false,
      theme: buildAmuwakTheme(),
      home: const LoginScreen(),
    );
  }
}
