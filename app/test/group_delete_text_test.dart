import 'package:flutter_test/flutter_test.dart';
import 'package:group_planner/features/groups/group_page.dart';

void main() {
  test('the delete warning uses the counts once they load', () {
    expect(deletionWarning((members: 4, upcomingPlans: 2, ideas: 1)), [
      '• 2 upcoming plans will be removed from everyone’s schedules.',
      '• 1 idea with no date yet will be deleted.',
      '• Its types and invite links are deleted.',
      '• Activities aren’t deleted; they stay with the people who added them.',
      '• The other 3 members and anyone in its plans will be notified.',
    ]);
  });

  test('before the counts load, or for a group of one', () {
    expect(deletionWarning(null).first, '• Its plans will be removed from everyone’s schedules.');
    expect(deletionWarning(null).last, '• Anyone in its plans will be notified.');
    final solo = deletionWarning((members: 1, upcomingPlans: 1, ideas: 0));
    expect(solo.first, '• 1 upcoming plan will be removed from everyone’s schedules.');
    expect(solo.last, '• Anyone in its plans will be notified.');
  });
}
