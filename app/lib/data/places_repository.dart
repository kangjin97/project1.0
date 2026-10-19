import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'geo.dart';

SupabaseClient get _db => Supabase.instance.client;

/// A place Google suggests for what's been typed (#73).
class PlaceSuggestion {
  PlaceSuggestion({required this.placeId, required this.mainText, required this.secondaryText});

  factory PlaceSuggestion.fromJson(Map<String, dynamic> j) => PlaceSuggestion(
        placeId: j['placeId'] as String,
        mainText: (j['mainText'] as String?) ?? (j['text'] as String? ?? ''),
        secondaryText: (j['secondaryText'] as String?) ?? '',
      );

  final String placeId;

  /// The place's name, e.g. "Changi Beach Park".
  final String mainText;

  /// Where it is, e.g. "Nicoll Drive, Singapore". Can be empty.
  final String secondaryText;

  /// What goes into the Location field when picked: name first, then where.
  String get label => secondaryText.isEmpty ? mainText : '$mainText, $secondaryText';
}

/// Why place search couldn't answer, in words for the user.
class PlaceSearchException implements Exception {
  PlaceSearchException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Where some Google places are, for the "Near…" filter (#94). [error] says
/// why some couldn't be placed (daily limit, not set up), or is null.
class PlaceCoordinates {
  const PlaceCoordinates(this.byPlace, [this.error]);

  final Map<String, GeoPoint> byPlace;
  final String? error;
}

/// Why the device's location couldn't be read, in words for the user.
class LocationException implements Exception {
  LocationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PlacesRepository {
  /// Suggestions for [input] from the `places` Edge Function, which calls
  /// Google and counts the search against the caller's daily quota. Under 3
  /// characters returns nothing without a call.
  Future<List<PlaceSuggestion>> suggest(String input) async {
    final q = input.trim();
    if (q.length < 3) return [];
    try {
      final res = await _db.functions.invoke('places', body: {'input': q, 'languageCode': 'en'});
      final rows = (res.data as Map?)?['suggestions'] as List? ?? const [];
      return [for (final r in rows) PlaceSuggestion.fromJson(Map<String, dynamic>.from(r as Map))];
    } on FunctionException catch (e) {
      final details = e.details;
      final message = details is Map ? details['error'] as String? : null;
      throw PlaceSearchException(message ?? 'Place search is unavailable right now.');
    }
  }

  /// Coordinates for [placeIds] from the `place-coordinates` Edge Function: its
  /// cache when fresh (Google allows keeping them 30 days), else Google, counted
  /// against the caller's daily quota. Asks 50 at a time.
  Future<PlaceCoordinates> coordinates(Iterable<String> placeIds) async {
    final ids = placeIds.toSet().toList();
    final found = <String, GeoPoint>{};
    String? error;
    for (var i = 0; i < ids.length; i += 50) {
      try {
        final res = await _db.functions.invoke('place-coordinates',
            body: {'placeIds': ids.sublist(i, min(i + 50, ids.length))});
        final data = Map<String, dynamic>.from(res.data as Map);
        final rows = Map<String, dynamic>.from(data['coordinates'] as Map? ?? const {});
        for (final MapEntry(:key, :value) in rows.entries) {
          final c = Map<String, dynamic>.from(value as Map);
          found[key] = GeoPoint((c['lat'] as num).toDouble(), (c['lng'] as num).toDouble());
        }
        error ??= data['error'] as String?;
      } on FunctionException catch (e) {
        final details = e.details;
        error ??= (details is Map ? details['error'] as String? : null) ?? 'Distances are unavailable right now.';
      }
    }
    return PlaceCoordinates(found, error);
  }

  /// The device's approximate position ("Use my location"). It's used on the
  /// device only and never sent anywhere.
  Future<GeoPoint> currentPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw LocationException('Location is turned off on this device.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      throw LocationException('EasyPlan isn’t allowed to use your location. Search for a place instead, or allow it in settings.');
    }
    final p = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 15)),
    );
    return GeoPoint(p.latitude, p.longitude);
  }
}

final placesRepositoryProvider = Provider((_) => PlacesRepository());

/// Coordinates for a set of place IDs, keyed by [placeKey].
final placeCoordinatesProvider = FutureProvider.autoDispose.family<PlaceCoordinates, String>((ref, key) =>
    key.isEmpty ? Future.value(const PlaceCoordinates({})) : ref.watch(placesRepositoryProvider).coordinates(key.split(',')));

/// The key for [placeCoordinatesProvider]: the sorted place IDs joined with ','.
String placeKey(Iterable<String?> placeIds) => (placeIds.whereType<String>().toSet().toList()..sort()).join(',');

/// Opens [location] in Google Maps: the exact place when one was picked
/// ([placeId]), otherwise a search for the text. These links need no API key.
Uri googleMapsUri(String location, {String? placeId}) => Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': location,
      'query_place_id': ?placeId,
    });
