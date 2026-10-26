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

  test('newest first, and activities saved together (an import) in name order (#111)', () {
    Activity at(String name, DateTime createdAt) =>
        Activity(id: name, ownerId: 'u1', name: name, createdAt: createdAt, updatedAt: createdAt);
    final batch = DateTime.utc(2026, 10, 26, 8, 35);
    final list = [
      at('Bulk test 111', batch),
      at('older', DateTime.utc(2026, 10, 1)),
      at('bulk test 002', batch),
      at('Newer', DateTime.utc(2026, 10, 27)),
      at('Bulk test 010', batch),
    ]..sort(Activity.newestFirst);
    expect([for (final a in list) a.name], ['Newer', 'bulk test 002', 'Bulk test 010', 'Bulk test 111', 'older']);
  });
}
