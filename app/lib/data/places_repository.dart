import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
}

final placesRepositoryProvider = Provider((_) => PlacesRepository());

/// Opens [location] in Google Maps: the exact place when one was picked
/// ([placeId]), otherwise a search for the text. These links need no API key.
Uri googleMapsUri(String location, {String? placeId}) => Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': location,
      'query_place_id': ?placeId,
    });
