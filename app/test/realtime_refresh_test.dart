import 'package:flutter_test/flutter_test.dart';
import 'package:group_planner/data/activities_repository.dart';
import 'package:group_planner/data/groups_repository.dart';
import 'package:group_planner/data/notifications_repository.dart';
import 'package:group_planner/data/realtime_repository.dart';
import 'package:group_planner/data/schedule_repository.dart';

void main() {
  test('a group message refreshes that group only', () {
    final affected = providersAffectedBy('group:g1', 'group_activities');
    expect(affected, contains(groupActivitiesProvider('g1')));
    expect(affected, contains(groupHistoryProvider('g1')));
    expect(affected, isNot(contains(groupActivitiesProvider('g2'))));
    expect(affected, isNot(contains(groupActivitiesProvider)));
  });

  test('a user message refreshes every group, since one change can touch several', () {
    final affected = providersAffectedBy('user:u1', 'activities');
    expect(affected, contains(groupActivitiesProvider));
    expect(affected, contains(myActivitiesProvider));
  });

  test('notifications keep the badge and the invitations live', () {
    final affected = providersAffectedBy('user:u1', 'notifications');
    expect(affected, containsAll([unreadCountProvider, notificationsProvider, invitationsProvider]));
  });

  test('answering an invitation elsewhere clears it here', () {
    expect(providersAffectedBy('user:u1', 'group_invitations'), contains(invitationsProvider));
  });

  test('plans refresh every schedule view', () {
    expect(providersAffectedBy('group:g1', 'schedule_participants'), contains(scheduleProvider));
    expect(providersAffectedBy('user:u1', 'schedule_entries'), contains(scheduleProvider));
  });

  test('after a reconnect everything for the topic is refreshed', () {
    final group = providersAffectedBy('group:g1', anyTable);
    expect(group, containsAll([groupActivitiesProvider('g1'), membersProvider('g1'), typesProvider('g1'), scheduleProvider]));
    expect(group, isNot(contains(unreadCountProvider)), reason: 'notifications are on the user topic');
    expect(providersAffectedBy('user:u1', anyTable), contains(unreadCountProvider));
  });

  test('unknown tables refresh nothing', () {
    expect(providersAffectedBy('group:g1', 'something_new'), isEmpty);
  });
}
