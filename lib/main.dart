import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'src/auth/login_screen.dart';
import 'src/bootstrap/app_bootstrap.dart';
import 'src/shared/widgets/app_theme.dart';

Future<void> main() async {
  await AppBootstrap.initialize();
  runApp(const ProviderScope(child: AmuwakStaffApp()));
}

class AmuwakStaffApp extends StatelessWidget {
  const AmuwakStaffApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Amuwak Staff',
      debugShowCheckedModeBanner: false,
      theme: buildAmuwakTheme(),
      home: const LoginScreen(),
    );
  }
}
