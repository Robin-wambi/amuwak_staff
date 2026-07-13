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

  /// Sign in with a real email + password. Email is trimmed and lower-cased so
  /// that casing/whitespace differences don't cause spurious auth failures.
  Future<void> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    try {
      await _goTrue.signInWithPassword(
        email: _normalizeEmail(email),
        password: password,
      );
    } on AuthException catch (e) {
      throw AuthFailure(e.message);
    }
  }

  /// Set the signed-in user's password. Used both when accepting an invite
  /// (the invite link establishes a session, then the user picks a password)
  /// and when completing a password reset.
  Future<void> updatePassword(String password) async {
    try {
      await _goTrue.updateUser(UserAttributes(password: password));
    } on AuthException catch (e) {
      throw AuthFailure(e.message);
    }
  }

  /// Send a password-reset email. The redirect target is the project's Site URL
  /// configured in Supabase, so no URL is hard-coded in the app.
  Future<void> sendPasswordReset(String email) async {
    try {
      await _goTrue.resetPasswordForEmail(_normalizeEmail(email));
    } on AuthException catch (e) {
      throw AuthFailure(e.message);
    }
  }

  static String _normalizeEmail(String email) => email.trim().toLowerCase();

  Future<void> signOut() => _goTrue.signOut();

  Session? get currentSession => _goTrue.currentSession;
  User?    get currentUser    => _goTrue.currentUser;
  Stream<AuthState> get authStateChanges => _goTrue.onAuthStateChange;
}
