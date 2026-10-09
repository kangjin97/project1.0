import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// The device's IANA time zone (e.g. "Asia/Singapore"); UTC if unknown.
Future<String> localTimezone() async {
  try {
    return (await FlutterTimezone.getLocalTimezone()).identifier;
  } catch (_) {
    return 'UTC';
  }
}

/// The time zone the app shows times in: the user's profile zone (chosen at
/// sign-up from the device, changeable on the profile page).
///
/// Static so models can convert while parsing; widgets that depend on it
/// watch [timezoneProvider] to rebuild when it changes.
class AppClock {
  static tz.Location _location = tz.UTC;
  static String _deviceZone = 'UTC';

  static tz.Location get location => _location;
  static String get zoneName => _location.name;

  /// The device's own zone, for sign-up and the "use this device" shortcut.
  static String get deviceZone => _deviceZone;

  /// True when the app shows times in a different zone from the device.
  static bool get differsFromDevice => !_sameZone(_location.name, _deviceZone);

  static Future<void> init() async {
    tzdata.initializeTimeZones();
    _deviceZone = await localTimezone();
    use(_deviceZone);
  }

  /// Switches the display zone. Unknown names keep the current zone.
  static void use(String name) {
    try {
      _location = tz.getLocation(name);
    } catch (_) {
      // UTC isn't in the location table under that exact name in every version.
      if (name == 'UTC') _location = tz.UTC;
    }
  }

  static tz.TZDateTime now() => tz.TZDateTime.now(_location);

  /// Today's date in the display zone.
  static DateTime today() {
    final n = now();
    return DateTime(n.year, n.month, n.day);
  }

  /// An instant (e.g. from the server) as wall-clock time in the display zone.
  static tz.TZDateTime inZone(DateTime instant) => tz.TZDateTime.from(instant, _location);

  /// A wall-clock time in the display zone (for times the user picks).
  static tz.TZDateTime at(int year, int month, int day, [int hour = 0, int minute = 0]) =>
      tz.TZDateTime(_location, year, month, day, hour, minute);

  /// Current offset from UTC in the display zone (or [name]), e.g. "UTC+08:00".
  static String offsetLabel([String? name]) {
    final loc = name == null ? _location : _tryLocation(name);
    if (loc == null) return '';
    return formatOffset(tz.TZDateTime.now(loc).timeZoneOffset.inMinutes);
  }

  static tz.Location? _tryLocation(String name) {
    try {
      return name == 'UTC' ? tz.UTC : tz.getLocation(name);
    } catch (_) {
      return null;
    }
  }

  static bool _sameZone(String a, String b) {
    if (a == b) return true;
    // Different names for the same rules (e.g. Singapore vs Kuala Lumpur) count as the same.
    final la = _tryLocation(a), lb = _tryLocation(b);
    if (la == null || lb == null) return false;
    final n = DateTime.now();
    return tz.TZDateTime.from(n, la).timeZoneOffset == tz.TZDateTime.from(n, lb).timeZoneOffset;
  }
}

/// "UTC+08:00", "UTC−03:00", "UTC+05:45", "UTC±00:00".
String formatOffset(int minutes) {
  if (minutes == 0) return 'UTC±00:00';
  final sign = minutes > 0 ? '+' : '−';
  final m = minutes.abs();
  return 'UTC$sign${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
}

/// The display zone name. Loads the profile's zone after sign-in and rebuilds
/// anything that watches it (schedules refetch, dates re-render).
class TimezoneController extends Notifier<String> {
  StreamSubscription<AuthState>? _sub;

  @override
  String build() {
    _sub = Supabase.instance.client.auth.onAuthStateChange.listen((s) {
      if (s.session != null) _loadFromProfile();
    });
    ref.onDispose(() => _sub?.cancel());
    // Already signed in (restored session): don't wait for an auth event.
    if (Supabase.instance.client.auth.currentUser != null) Future.microtask(_loadFromProfile);
    return AppClock.zoneName;
  }

  Future<void> _loadFromProfile() async {
    final db = Supabase.instance.client;
    final user = db.auth.currentUser;
    if (user == null) return;
    try {
      final row = await db.from('profiles').select('timezone').eq('id', user.id).single();
      _apply(row['timezone'] as String? ?? 'UTC');
    } catch (_) {
      // Keep the device zone if the profile can't be read.
    }
  }

  /// Saves a new zone on the profile and switches the app to it.
  Future<void> change(String name) async {
    final db = Supabase.instance.client;
    await db.from('profiles').update({'timezone': name}).eq('id', db.auth.currentUser!.id);
    _apply(name);
  }

  void _apply(String name) {
    AppClock.use(name);
    state = AppClock.zoneName;
  }
}

final timezoneProvider = NotifierProvider<TimezoneController, String>(TimezoneController.new);

/// Zones for the picker, from the database (current offsets, daylight saving included).
typedef TimezoneOption = ({String name, String region, String city, int offsetMinutes});

final timezoneOptionsProvider = FutureProvider<List<TimezoneOption>>((ref) async {
  final rows = await Supabase.instance.client.rpc('list_timezones') as List;
  return [
    for (final r in rows.cast<Map<String, dynamic>>())
      (
        name: r['name'] as String,
        region: r['region'] as String,
        city: r['city'] as String,
        offsetMinutes: r['offset_minutes'] as int,
      ),
  ];
});
