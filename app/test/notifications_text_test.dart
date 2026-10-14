import 'package:flutter_test/flutter_test.dart';
import 'package:group_planner/data/models.dart';
import 'package:group_planner/features/notifications/notifications_page.dart';

AppNotification note(String kind, {
  String? actor = 'alice',
  String? group = 'Hikers',
  String? status,
  String? entryId = 'e1',
  String? title = 'Dinner',
  bool allDay = false,
  DateTime? date,
  DateTime? start,
  int clashes = 0,
}) =>
    AppNotification(
      id: 'n1',
      kind: kind,
      createdAt: DateTime(2026, 10, 14, 9),
      actorName: actor,
      groupName: group,
      invitationStatus: status,
      entryId: entryId,
      entryTitle: title,
      entryAllDay: allDay,
      entryDate: date,
      entryStartAt: start,
      clashCount: clashes,
    );

void main() {
  test('invitations name the inviter, the group and the status', () {
    final t = describeNotification(note('group_invitation', status: 'pending', entryId: null, title: null));
    expect(t.title, 'alice invited you to Hikers');
    expect(t.detail, 'Tap to accept or decline');
    expect(describeNotification(note('group_invitation', status: 'accepted')).detail, 'You joined');
  });

  test('being added to a plan shows the group and when', () {
    final t = describeNotification(note('added_to_entry', start: DateTime(2026, 10, 18, 19)));
    expect(t.title, 'alice added you to Dinner');
    expect(t.detail, 'Hikers · Sun 18 Oct, 7:00 PM');
    expect(describeNotification(note('added_to_entry', allDay: true, date: DateTime(2026, 10, 18))).detail,
        'Hikers · Sun 18 Oct, all day');
  });

  test('clashes say how many plans and who added you', () {
    final t = describeNotification(note('schedule_clash', clashes: 2, start: DateTime(2026, 10, 18, 19)));
    expect(t.title, 'Dinner clashes with 2 of your plans');
    expect(t.detail, 'alice added you anyway · Sun 18 Oct, 7:00 PM');
    expect(describeNotification(note('schedule_clash', clashes: 1)).title, 'Dinner clashes with 1 of your plans');
  });

  test('hidden plans, groups and deleted users read naturally', () {
    final t = describeNotification(note('added_to_entry', actor: null, group: null, entryId: null, title: null));
    expect(t.title, 'Someone added you to a plan');
    expect(t.detail, '');
    expect(describeNotification(note('group_invitation', group: null)).title, 'alice invited you to a group');
    expect(planWhen(note('added_to_entry')), 'No date yet');
  });

  test('time ago', () {
    final now = DateTime(2026, 10, 14, 12);
    expect(timeAgo(now.subtract(const Duration(seconds: 20)), now), 'Just now');
    expect(timeAgo(now.subtract(const Duration(minutes: 5)), now), '5 min ago');
    expect(timeAgo(now.subtract(const Duration(hours: 3)), now), '3 h ago');
    expect(timeAgo(now.subtract(const Duration(days: 2)), now), '2 d ago');
    expect(timeAgo(DateTime(2026, 9, 1, 8), now), '1 Sep');
  });
}
