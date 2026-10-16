import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:group_planner/data/ai_fill_repository.dart';

void main() {
  test('reads the suggested fields, place, label and preview image', () {
    final fill = AiFill.fromJson({
      'source': 'youtube',
      'fields': {
        'name': 'Ramen at Ippudo',
        'description': 'Rich tonkotsu ramen.',
        'location': 'Ippudo, Mandarin Gallery, Singapore',
        'placeId': 'ChIJabcdefghij',
        'priceMin': 18,
        'priceMax': 25.5,
        'currency': 'SGD',
        'url': 'https://www.youtube.com/watch?v=x',
        'label': {'name': 'Food', 'isNew': false},
      },
      'photo': {'data': base64Encode([1, 2, 3]), 'mediaType': 'image/png'},
    });
    expect(fill.name, 'Ramen at Ippudo');
    expect(fill.placeId, 'ChIJabcdefghij');
    expect((fill.priceMin, fill.priceMax), (18.0, 25.5));
    expect((fill.labelName, fill.labelIsNew), ('Food', false));
    expect(fill.photo, [1, 2, 3]);
    expect(fill.photoExtension, 'png');
  });

  test('missing pieces stay empty', () {
    final fill = AiFill.fromJson({
      'fields': {'name': 'Somewhere', 'label': null},
      'photo': null,
    });
    expect(fill.description, isNull);
    expect(fill.location, isNull);
    expect(fill.labelName, isNull);
    expect(fill.photo, isNull);
    expect(fill.photoExtension, 'jpg');
  });
}
