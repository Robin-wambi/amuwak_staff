import 'package:supabase_flutter/supabase_flutter.dart';

class AuthFailure implements Exception {
  AuthFailure(this.message);
  final String message;
  @override
  String toString() => 'AuthFailure: $message';
}

class AuthService {
  AuthService({GoTrueClient? goTrue})
      : _goTrue = goTrue ?? Supabase.instance.client.auth;

  final GoTrueClient _goTrue;

  static const _emailSuffix = '@amuwak.local';

  /// Sign in via the username + PIN scheme. `username` is what staff type at
  /// the login screen; we compose `<username>@amuwak.local` and use the PIN
  /// as the password. Supabase Auth is unaware of the scheme — it sees a
  /// plain email/password sign-in.
  Future<void> signInWithUsernamePin({
    required String username,
    required String pin,
  }) async {
    try {
      await _goTrue.signInWithPassword(
        email: '${username.toLowerCase()}$_emailSuffix',
        password: pin,
      );
    } on AuthException catch (e) {
      throw AuthFailure(e.message);
    }
  }

  Future<void> signOut() => _goTrue.signOut();

  Session? get currentSession => _goTrue.currentSession;
  User?    get currentUser    => _goTrue.currentUser;
  Stream<AuthState> get authStateChanges => _goTrue.onAuthStateChange;
}
