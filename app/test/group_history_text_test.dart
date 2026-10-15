import 'package:flutter_test/flutter_test.dart';
import 'package:group_planner/data/models.dart';
import 'package:group_planner/features/groups/group_history_page.dart';

const ann = 'u-ann';
const ben = 'u-ben';

ChangeEntry change(
  String entityType,
  String action, {
  String? actorId = ann,
  String? entityId = 'x1',
  String? subject = 'Beach day',
  String? person,
  String? from,
  String? to,
  Map<String, dynamic>? before,
  Map<String, dynamic>? after,
}) =>
    ChangeEntry(
      id: 1,
      entityType: entityType,
      entityId: entityId,
      action: action,
      actorId: actorId,
      actorUsername: 'ann',
      createdAt: DateTime(2026, 10, 15, 9),
      subjectName: subject,
      personUsername: person,
      fromTypeName: from,
      toTypeName: to,
      before: before,
      after: after,
    );

void main() {
  test('activity edits name the field and the activity', () {
    expect(
      describeGroupChange(change('activity', 'updated', before: {'price_max': 20}, after: {'price_max': 30})),
      'changed max price from “20” to “30” on “Beach day”',
    );
    expect(describeGroupChange(change('activity_photo', 'created')), 'added a photo to “Beach day”');
  });

  test('sharing and type changes name the types', () {
    expect(describeGroupChange(change('group_activity', 'created', to: 'Food')), 'shared “Beach day” under Food');
    expect(describeGroupChange(change('group_activity', 'type_changed', from: 'Food', to: 'Outdoors')),
        'moved “Beach day” from Food to Outdoors');
    expect(describeGroupChange(change('group_activity', 'type_changed', to: 'Food')), 'moved “Beach day” to Food');
    expect(describeGroupChange(change('group_activity', 'deleted')), 'removed “Beach day” from the group');
  });

  test('gone or hidden activities and plans read generically', () {
    expect(describeGroupChange(change('group_activity', 'deleted', subject: null)), 'removed an activity from the group');
    expect(describeGroupChange(change('schedule_entry', 'deleted', subject: null)), 'removed a plan from the schedule');
  });

  test('types and merges', () {
    expect(describeGroupChange(change('activity_type', 'created', subject: 'Food')), 'added the type “Food”');
    expect(describeGroupChange(change('activity_type', 'updated', subject: 'Eats', before: {'name': 'Food'})),
        'renamed the type “Food” to “Eats”');
    expect(describeGroupChange(change('type_merge', 'created', subject: 'yummy', to: 'Food')), 'merged “yummy” into Food');
    expect(describeGroupChange(change('type_merge', 'deleted', subject: 'yummy')), 'undid the merge of “yummy”');
  });

  test('plans', () {
    expect(describeGroupChange(change('schedule_entry', 'created', subject: 'Picnic', after: {'activity_id': null})),
        'planned the event “Picnic”');
    expect(describeGroupChange(change('schedule_entry', 'created', after: {'activity_id': 'a1'})), 'planned “Beach day”');
    // An event is named as it was planned, even after an activity replaced it.
    expect(
      describeGroupChange(change('schedule_entry', 'created', subject: 'Marco’s', after: {'activity_id': null, 'title': 'Eat some steak'})),
      'planned the event “Eat some steak”',
    );
    expect(
      describeGroupChange(ChangeEntry(
        entityType: 'schedule_entry',
        action: 'event_replaced',
        actorUsername: 'ben',
        createdAt: DateTime(2026, 10, 15),
        subjectName: 'Marco’s',
        eventTitle: 'Eat some steak',
      )),
      'replaced the event “Eat some steak” with “Marco’s”',
    );
    expect(describeGroupChange(change('schedule_entry', 'updated', after: {'start_at': 'x'})), 'changed the time of “Beach day”');
    expect(
      describeGroupChange(change('schedule_entry', 'updated', subject: 'Steak', before: {'title': 'Eat'}, after: {'title': 'Steak'})),
      'renamed the event “Eat” to “Steak”',
    );
    expect(
      describeGroupChange(change('schedule_entry', 'clash_override', after: {
        'clashes': [
          {'username': 'ben'},
          {'username': 'ben'},
        ],
      })),
      'went ahead with “Beach day” despite clashes for @ben',
    );
  });

  test('joining or leaving yourself vs. someone else doing it', () {
    expect(describeGroupChange(change('schedule_participant', 'created', person: 'ben', after: {'user_id': ben})),
        'added @ben to “Beach day”');
    expect(describeGroupChange(change('schedule_participant', 'deleted', actorId: ben, person: 'ben', before: {'user_id': ben})),
        'left “Beach day”');
    expect(describeGroupChange(change('group_member', 'created', entityId: ben, actorId: ben, person: 'ben', after: {'role': 'member'})),
        'joined the group');
    expect(describeGroupChange(change('group_member', 'created', entityId: ann, person: 'ann', after: {'role': 'owner'})),
        'created the group');
    expect(describeGroupChange(change('group_member', 'deleted', entityId: ben, person: 'ben')),
        'removed @ben from the group');
    expect(
        describeGroupChange(change('group_member', 'updated', entityId: ben, person: 'ben',
            before: {'role': 'member'}, after: {'role': 'owner'})),
        'made @ben the owner');
  });

  test('invite links and invitations', () {
    expect(describeGroupChange(change('invite_link', 'created', subject: null)), 'created an invite link');
    expect(describeGroupChange(change('invite_link', 'updated', subject: null, after: {'revoked_at': 'x'})),
        'revoked an invite link');
    expect(describeGroupChange(change('invitation', 'created', subject: null, person: 'dan')), 'invited @dan');
    expect(
      describeGroupChange(change('invitation', 'updated', subject: null, person: 'dan', after: {'status': 'cancelled'})),
      'cancelled the invitation for @dan',
    );
    expect(
      describeGroupChange(change('invitation', 'updated', subject: null, person: 'dan', after: {'status': 'declined'})),
      'declined the invitation',
    );
  });

  test('deleted accounts still read correctly', () {
    // The profile is gone, but the ids in the log still match.
    expect(describeGroupChange(change('group_member', 'deleted', entityId: ben, actorId: ben)), 'left the group');
    expect(describeGroupChange(change('group_member', 'deleted', entityId: ben)), 'removed a deleted user from the group');
  });
}
