import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';

SupabaseClient get _db => Supabase.instance.client;

/// Signing up, signing in and password resets. Session state (`currentUser`,
/// `onAuthStateChange`, `signOut`) is read directly where it's needed.
/// Shown when signing up with an email that already has an account (owner's
/// choice, #87: say so plainly rather than hide it).
const alreadyRegisteredMessage =
    'This email is already registered. Sign in, continue with Google, or use “Forgot password?” to set a password.';

/// Shown for a wrong email or password; a Google account has no password until one is set.
const wrongPasswordMessage =
    'Wrong username, email or password. If you signed up with Google, continue with Google or use “Forgot password?” to set a password.';

/// Whether a sign-in entry is an email (it has an @) rather than a username.
bool isEmailLogin(String login) => login.contains('@');

class AuthRepository {
  /// The trigger `handle_new_user` creates the profile from this metadata.
  /// Returns true when the account must be confirmed by email before signing in.
  Future<bool> signUp({
    required String email,
    required String password,
    required String username,
    required String displayName,
    required String timezone,
  }) async {
    final AuthResponse res;
    try {
      res = await _db.auth.signUp(
        email: email.trim(),
        password: password,
        data: {'username': username, 'display_name': displayName.trim(), 'timezone': timezone},
      );
    } on AuthException catch (e) {
      // Without email confirmation (the local stack), Auth refuses a taken email.
      if (e.code == 'user_already_exists' || e.code == 'email_exists') {
        throw const AuthException(alreadyRegisteredMessage, code: 'user_already_exists');
      }
      rethrow;
    }
    // With email confirmation on (the cloud), Auth doesn't refuse a taken email;
    // it answers with a user that has no identities and sends nothing.
    if (res.user != null && (res.user!.identities?.isEmpty ?? false)) {
      throw const AuthException(alreadyRegisteredMessage, code: 'user_already_exists');
    }
    return res.session == null;
  }

  /// Signs in with an email or, without an @, a username (#107).
  Future<void> signIn({required String login, required String password}) async {
    if (!isEmailLogin(login)) return _signInWithUsername(login, password);
    try {
      await _db.auth.signInWithPassword(email: login.trim(), password: password);
    } on AuthException catch (e) {
      if (e.code == 'invalid_credentials') throw AuthException(wrongPasswordMessage, code: e.code);
      rethrow;
    }
  }

  /// Auth signs in by email only, so the `username-sign-in` Edge Function looks
  /// the email up and signs in for us; it answers with just a refresh token, so
  /// the account's email never reaches the app.
  Future<void> _signInWithUsername(String username, String password) async {
    const unavailable = 'Signing in is unavailable right now. Try your email.';
    final FunctionResponse res;
    try {
      res = await _db.functions.invoke('username-sign-in', body: {'username': username.trim(), 'password': password});
    } on FunctionException catch (e) {
      final details = e.details;
      final code = details is Map ? details['code'] as String? : null;
      if (code == 'invalid_credentials') throw const AuthException(wrongPasswordMessage, code: 'invalid_credentials');
      throw AuthException((details is Map ? details['error'] as String? : null) ?? unavailable, code: code);
    }
    final token = (res.data as Map?)?['refresh_token'] as String?;
    if (token == null) throw const AuthException(unavailable);
    await _db.auth.setSession(token);
  }

  /// Leaves the app for Google's sign-in page; Google sends the browser back to
  /// [returnTo] (a path in this app) with a code that Supabase turns into a session.
  /// Must be an allowed redirect URL (`<APP_URL>/**`).
  Future<void> signInWithGoogle({String returnTo = '/schedule'}) => _db.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: '${AppConfig.appUrl}/?next=${Uri.encodeComponent(returnTo)}',
      );

  /// Google's picture for the signed-in user, if they came through Google.
  String? get googlePhotoUrl {
    final meta = _db.auth.currentUser?.userMetadata;
    final url = (meta?['avatar_url'] ?? meta?['picture']) as String?;
    if (url == null || !url.startsWith('https://')) return null;
    // Google serves a 96 px square by default; ask for a sharper one.
    return url.replaceFirst(RegExp(r'=s\d+-c$'), '=s256-c');
  }

  /// Emails a link that opens `/reset-password` (allowed in the project's redirect URLs).
  Future<void> sendPasswordReset(String email) =>
      _db.auth.resetPasswordForEmail(email.trim(), redirectTo: '${AppConfig.appUrl}/reset-password');

  /// Sets the password during the recovery session a reset link starts.
  Future<void> setNewPassword(String password) => _db.auth.updateUser(UserAttributes(password: password));
}

final authRepositoryProvider = Provider((_) => AuthRepository());
