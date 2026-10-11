import 'package:flutter/foundation.dart';

/// Build-time settings, passed with `--dart-define` (or `--dart-define-from-file`,
/// see `env/prod.example.json` and `scripts/`).
///
/// Defaults point at the local stack started with `supabase start`, so a plain
/// `flutter run` works for development. Release builds refuse to start with
/// these defaults (see `main.dart`).
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

  /// Public address of the hosted web app, e.g. https://easyplan.netlify.app.
  /// Invite links and email links (password reset) point here, so they open
  /// for anyone, on any device.
  static const _appUrl = String.fromEnvironment('APP_URL');

  /// The Android emulator reaches the host machine at 10.0.2.2, not 127.0.0.1.
  static String get supabaseUrl {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return _url.replaceFirst('127.0.0.1', '10.0.2.2');
    }
    return _url;
  }

  static String get appUrl {
    if (_appUrl.isNotEmpty) return _appUrl.endsWith('/') ? _appUrl.substring(0, _appUrl.length - 1) : _appUrl;
    return kIsWeb ? Uri.base.origin : 'http://127.0.0.1:3000';
  }

  /// True when built against the local development stack.
  static bool get isLocalBackend => _url.contains('127.0.0.1') || _url.contains('localhost');

  static String get privacyPolicyUrl => '$appUrl/privacy.html';

  /// A link that opens a group invite in the app or the web app.
  static String inviteLink(String token) => '$appUrl/join/$token';
}
