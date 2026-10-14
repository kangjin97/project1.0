import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';

SupabaseClient get _db => Supabase.instance.client;

/// Signing up, signing in and password resets. Session state (`currentUser`,
/// `onAuthStateChange`, `signOut`) is read directly where it's needed.
class AuthRepository {
  /// The trigger `handle_new_user` creates the profile from this metadata.
  Future<void> signUp({
    required String email,
    required String password,
    required String username,
    required String displayName,
    required String timezone,
  }) =>
      _db.auth.signUp(
        email: email.trim(),
        password: password,
        data: {'username': username, 'display_name': displayName.trim(), 'timezone': timezone},
      );

  Future<void> signIn({required String email, required String password}) =>
      _db.auth.signInWithPassword(email: email.trim(), password: password);

  /// Emails a link that opens `/reset-password` (allowed in the project's redirect URLs).
  Future<void> sendPasswordReset(String email) =>
      _db.auth.resetPasswordForEmail(email.trim(), redirectTo: '${AppConfig.appUrl}/reset-password');

  /// Sets the password during the recovery session a reset link starts.
  Future<void> setNewPassword(String password) => _db.auth.updateUser(UserAttributes(password: password));
}

final authRepositoryProvider = Provider((_) => AuthRepository());
