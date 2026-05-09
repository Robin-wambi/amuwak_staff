import 'package:flutter/material.dart';
import 'src/auth/login_screen.dart';
import 'src/shared/widgets/app_theme.dart';

void main() {
  runApp(const AmuwakStaffApp());
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