import 'package:flutter/material.dart';
import '../dashboard/staff_dashboard_screen.dart';
import '../shared/widgets/app_theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  String? _errorMessage;

  void _login() {
    setState(() {
      _errorMessage = null;
    });

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email == 'staff@amuwak.com' && password == 'password123') {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => const StaffDashboardScreen(),
        ),
      );
    } else {
      setState(() {
        _errorMessage = 'Invalid staff login details.';
      });
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: amuwakBackground,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: amuwakPrimary,
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: const Icon(
                      Icons.local_laundry_service_rounded,
                      color: amuwakDark,
                      size: 46,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Amuwak Staff',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      color: amuwakDark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Login to manage laundry orders',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _emailController,
                    decoration: const InputDecoration(
                      labelText: 'Email or phone',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Enter your email or phone';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Enter your password';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  if (_errorMessage != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _login,
                    child: const Text(
                      'Login',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Demo login: staff@amuwak.com / password123',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.black45,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
