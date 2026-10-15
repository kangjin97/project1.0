import 'package:flutter_test/flutter_test.dart';
import 'package:group_planner/data/models.dart';

Activity activity({String? url, List<ActivityPhoto> photos = const []}) => Activity(
      id: 'a1',
      ownerId: 'u1',
      name: 'Beach day',
      url: url,
      photos: photos,
      createdAt: DateTime.utc(2026, 10, 15),
      updatedAt: DateTime.utc(2026, 10, 15),
    );

void main() {
  test('has a link only when the link has text', () {
    expect(activity(url: 'https://example.com').hasLink, isTrue);
    expect(activity().hasLink, isFalse);
    expect(activity(url: '').hasLink, isFalse);
    expect(activity(url: '   ').hasLink, isFalse);
  });

  test('has photos when at least one is attached', () {
    expect(activity().hasPhotos, isFalse);
    expect(activity(photos: [ActivityPhoto(id: 'p1', storagePath: 'a1/x.jpg', position: 0)]).hasPhotos, isTrue);
  });
}
