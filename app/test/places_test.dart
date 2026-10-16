import 'package:flutter_test/flutter_test.dart';
import 'package:group_planner/data/activities_repository.dart';
import 'package:group_planner/data/places_repository.dart';

void main() {
  test('a suggestion reads name first, then where it is', () {
    final s = PlaceSuggestion.fromJson({
      'placeId': 'ChIJUzbaYws82jERXHKMRlUKIug',
      'text': 'Nicoll Drive, Changi Beach Park, Singapore',
      'mainText': 'Changi Beach Park',
      'secondaryText': 'Nicoll Drive, Singapore',
    });
    expect(s.label, 'Changi Beach Park, Nicoll Drive, Singapore');
    expect(PlaceSuggestion.fromJson({'placeId': 'ChIJabcdefghij', 'mainText': 'Singapore', 'secondaryText': ''}).label,
        'Singapore');
  });

  test('maps links open the exact place when there is one, else search the text', () {
    final exact = googleMapsUri('Changi Beach Park, Singapore', placeId: 'ChIJUzbaYws82jERXHKMRlUKIug');
    expect(exact.host, 'www.google.com');
    expect(exact.queryParameters, {
      'api': '1',
      'query': 'Changi Beach Park, Singapore',
      'query_place_id': 'ChIJUzbaYws82jERXHKMRlUKIug',
    });
    expect(googleMapsUri('somewhere nice').queryParameters, {'api': '1', 'query': 'somewhere nice'});
  });

  test('a place is only sent with location text', () {
    expect(ActivityInput(name: 'Beach', location: 'Changi', placeId: 'ChIJabcdefghij').toJson()['place_id'],
        'ChIJabcdefghij');
    expect(ActivityInput(name: 'Beach', location: '  ', placeId: 'ChIJabcdefghij').toJson()['place_id'], isNull);
    expect(ActivityInput(name: 'Beach', location: 'Changi').toJson()['place_id'], isNull);
  });
}
