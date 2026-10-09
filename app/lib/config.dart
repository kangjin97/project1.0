import 'package:flutter/foundation.dart';

/// Supabase connection settings.
///
/// Defaults point at the local stack started with `supabase start`. Override
/// for a hosted project with:
///   flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_PUBLISHABLE_KEY=...
class AppConfig {
  static const _url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'http://127.0.0.1:54321',
  );

  // The standard key every local Supabase stack uses; not a secret.
  static const publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH',
  );

  /// The Android emulator reaches the host machine at 10.0.2.2, not 127.0.0.1.
  static String get supabaseUrl {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return _url.replaceFirst('127.0.0.1', '10.0.2.2');
    }
    return _url;
  }
}
