import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:group_planner/data/places_repository.dart';
import 'package:group_planner/features/activities/place_field.dart';

/// Answers every search with the same place, and counts the searches.
class _FakePlaces extends PlacesRepository {
  int searches = 0;

  @override
  Future<List<PlaceSuggestion>> suggest(String input) async {
    searches++;
    return [PlaceSuggestion(placeId: 'ChIJ_fake_place_1', mainText: 'Changi Beach Park', secondaryText: 'Singapore')];
  }
}

void main() {
  late _FakePlaces places;
  late TextEditingController controller;
  String? placeId;

  Future<void> pump(WidgetTester tester, {String text = '', String? initialPlace}) async {
    places = _FakePlaces();
    controller = TextEditingController(text: text);
    placeId = initialPlace;
    await tester.pumpWidget(ProviderScope(
      overrides: [placesRepositoryProvider.overrideWithValue(places)],
      child: MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => PlaceField(
              controller: controller,
              placeId: placeId,
              onPlaceChanged: (id) => setState(() => placeId = id),
            ),
          ),
        ),
      ),
    ));
  }

  testWidgets('editing a picked place by hand drops it', (tester) async {
    await pump(tester, text: 'Changi Beach Park, Singapore', initialPlace: 'ChIJ_saved_place');
    expect(find.text('Exact place from Google Maps'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), 'Changi Beach Park, Singapore north gate');
    await tester.pump();
    expect(placeId, isNull);
    expect(find.text('Type to search Google Maps, or write any place'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
  });

  testWidgets('typing searches once after a pause, and picking keeps the place', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextFormField), 'cha');
    await tester.enterText(find.byType(TextFormField), 'chan');
    await tester.enterText(find.byType(TextFormField), 'changi');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(places.searches, 1, reason: 'only the text after the pause is searched');
    expect(find.text('Google Maps'), findsOneWidget, reason: 'attribution sits with the suggestions');

    await tester.tap(find.text('Changi Beach Park'));
    await tester.pump();
    expect(placeId, 'ChIJ_fake_place_1');
    expect(controller.text, 'Changi Beach Park, Singapore');
    expect(find.text('Google Maps'), findsNothing, reason: 'the list closes after a pick');
  });

  testWidgets('under 3 characters never searches', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextFormField), 'ch');
    await tester.pump(const Duration(milliseconds: 500));
    expect(places.searches, 0);
  });
}
