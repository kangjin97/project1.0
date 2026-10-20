import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:group_planner/data/calendar_export.dart';
import 'package:group_planner/data/itinerary.dart';
import 'package:group_planner/data/models.dart';
import 'package:group_planner/data/schedule_models.dart';

final gardens = GroupActivity(
  groupId: 'g1',
  typeId: 't1',
  typeName: 'Outdoors',
  sharedAt: DateTime.utc(2026, 10, 1),
  activity: Activity(
    id: 'a1',
    ownerId: 'u1',
    name: 'Gardens',
    location: 'Gardens by the Bay, Marina Gardens Drive, Singapore',
    priceMin: 0,
    priceMax: 32,
    url: 'https://www.gardensbythebay.com.sg/',
    description: 'Supertree Grove is free; domes need tickets.',
    createdAt: DateTime.utc(2026, 10, 1),
    updatedAt: DateTime.utc(2026, 10, 1),
  ),
);

ScheduleEntry plan(String id, {String? activityId, String? title, DateTime? start, DateTime? end, DateTime? date}) =>
    ScheduleEntry(
      id: id,
      groupId: 'g1',
      groupName: 'Foodies',
      activityId: activityId,
      activityName: activityId == null ? null : 'Gardens by the Bay',
      title: title,
      allDay: date != null,
      date: date,
      startAt: start,
      endAt: end,
      participants: [
        ScheduleParticipant(userId: 'u1', username: 'ann', displayName: 'Ann', status: 'added'),
        ScheduleParticipant(userId: 'u2', username: 'ben', status: 'added'),
      ],
    );

void main() {
  // 9:30–12:00 in Singapore (UTC+8).
  final timed = ItineraryItem.from(
      plan('e1', activityId: 'a1', start: DateTime.utc(2026, 10, 24, 1, 30), end: DateTime.utc(2026, 10, 24, 4)), gardens);
  final allDay = ItineraryItem.from(plan('e2', title: 'Beach day', date: DateTime(2026, 10, 25)), null);

  test('Google Calendar link for a timed plan, in UTC', () {
    final uri = googleCalendarUri(timed)!;
    expect(uri.host, 'calendar.google.com');
    expect(uri.path, '/calendar/render');
    expect(uri.queryParameters['action'], 'TEMPLATE');
    expect(uri.queryParameters['text'], 'Gardens by the Bay');
    expect(uri.queryParameters['dates'], '20261024T013000Z/20261024T040000Z');
    expect(uri.queryParameters['location'], 'Gardens by the Bay, Marina Gardens Drive, Singapore');
    final notes = uri.queryParameters['details']!;
    expect(notes, startsWith('Planned in Foodies on EasyPlan.\nGoing: Ann, ben\nPrice: SGD 0–32\nhttps://www.gardensbythebay.com.sg/'));
    expect(notes, endsWith('/groups/g1'));
  });

  test('all-day plans span the day; plans with no date get no link', () {
    expect(googleCalendarUri(allDay)!.queryParameters['dates'], '20261025/20261026');
    expect(googleCalendarUri(allDay)!.queryParameters.containsKey('location'), isFalse);
    expect(googleCalendarUri(ItineraryItem.from(plan('e3', title: 'Someday'), null)), isNull);
  });

  group('.ics file', () {
    final it = Itinerary.build(
      groupName: 'Foodies',
      from: DateTime(2026, 10, 24),
      to: DateTime(2026, 10, 25),
      entries: [
        timed.entry,
        allDay.entry,
        plan('e4', title: 'Late; night, out', start: DateTime(2026, 10, 24, 23), end: DateTime(2026, 10, 25, 1)),
      ],
      activities: [gardens],
    );
    final ics = toIcs(it, now: DateTime.utc(2026, 10, 20, 12));
    final lines = ics.split('\r\n');

    test('is a calendar with one event per plan', () {
      expect(lines.first, 'BEGIN:VCALENDAR');
      expect(ics, endsWith('END:VCALENDAR\r\n'));
      expect('BEGIN:VEVENT'.allMatches(ics).length, 3, reason: 'the late plan spans two days but is one event');
      expect(ics, contains('UID:e1@easyplan'));
      expect(ics, contains('DTSTART:20261024T013000Z\r\nDTEND:20261024T040000Z'));
      expect(ics, contains('DTSTART;VALUE=DATE:20261025\r\nDTEND;VALUE=DATE:20261026'));
      expect(ics, contains('DTSTAMP:20261020T120000Z'));
    });

    test('escapes text and folds long lines', () {
      expect(ics, contains(r'SUMMARY:Late\; night\, out'));
      expect(ics, contains(r'Going: Ann\, ben\n'));
      for (final l in lines) {
        expect(utf8.encode(l).length, lessThanOrEqualTo(75), reason: l);
      }
      // Unfolded, the location is whole again.
      expect(ics.replaceAll('\r\n ', ''), contains(r'LOCATION:Gardens by the Bay\, Marina Gardens Drive\, Singapore'));
    });
  });
}
