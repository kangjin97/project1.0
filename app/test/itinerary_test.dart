import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:group_planner/data/itinerary.dart';
import 'package:group_planner/data/models.dart';
import 'package:group_planner/data/schedule_models.dart';
import 'package:group_planner/features/groups/itinerary_export_sheet.dart';

GroupActivity shared(String id, String name, {String? location, String? placeId, double? min, double? max, String? url}) =>
    GroupActivity(
      groupId: 'g1',
      typeId: 't1',
      typeName: 'Outdoors',
      sharedAt: DateTime.utc(2026, 10, 1),
      activity: Activity(
        id: id,
        ownerId: 'u1',
        name: name,
        location: location,
        placeId: placeId,
        priceMin: min,
        priceMax: max,
        url: url,
        description: 'Nice.',
        createdAt: DateTime.utc(2026, 10, 1),
        updatedAt: DateTime.utc(2026, 10, 1),
      ),
    );

ScheduleEntry plan(String id, {String? activityId, String? title, DateTime? start, DateTime? end, DateTime? date}) =>
    ScheduleEntry(
      id: id,
      groupId: 'g1',
      groupName: 'Crew',
      activityId: activityId,
      activityName: activityId == null ? null : 'from activity',
      title: title,
      allDay: date != null,
      date: date,
      startAt: start,
      endAt: end,
      participants: [ScheduleParticipant(userId: 'u1', username: 'ann', displayName: 'Ann', status: 'added')],
    );

void main() {
  final sat = DateTime(2026, 10, 24), sun = DateTime(2026, 10, 25);
  final activities = [
    shared('a1', 'Gardens', location: 'Gardens by the Bay, Singapore', placeId: 'ChIJMxZ-kwQZ2jERdsqftXeWCWI', min: 0, max: 20),
    shared('a2', 'Dinner', location: 'Lau Pa Sat', min: 15, max: 30, url: 'https://example.com/menu'),
  ];
  final entries = [
    plan('e1', activityId: 'a2', start: DateTime(2026, 10, 24, 19), end: DateTime(2026, 10, 24, 21)),
    plan('e2', activityId: 'a1', start: DateTime(2026, 10, 24, 10), end: DateTime(2026, 10, 24, 12, 30)),
    plan('e3', title: 'Beach day', date: sun),
    plan('e4', title: 'Late night', start: DateTime(2026, 10, 24, 23), end: DateTime(2026, 10, 25, 1)),
    plan('idea', title: 'Someday'),
  ];
  final it = Itinerary.build(groupName: 'Crew', from: sat, to: sun, entries: entries, activities: activities);

  test('days hold their plans in order; plans with no date are left out', () {
    expect(it.days.map((d) => d.date), [sat, sun]);
    expect([for (final i in it.days[0].items) i.entry.id], ['e2', 'e1', 'e4']);
    expect([for (final i in it.days[1].items) i.entry.id], ['e3', 'e4'], reason: 'all-day first; the late plan runs past midnight');
    expect(it.planCount, 4);
    expect(it.rangeLabel, 'Sat 24 – Sun 25 Oct 2026');
  });

  test('items carry the activity details and times read naturally', () {
    final gardens = it.days[0].items.first;
    expect(gardens.title, 'from activity');
    expect(gardens.typeName, 'Outdoors');
    expect(gardens.timeLabel(sat), '10:00 AM – 12:30 PM');
    expect(gardens.mapsUri.toString(), contains('query_place_id=ChIJMxZ-kwQZ2jERdsqftXeWCWI'));
    final late = it.days[0].items.last;
    expect(late.timeLabel(sat), 'From 11:00 PM');
    expect(late.timeLabel(sun), 'Until 1:00 AM');
    expect(late.minutesOn(sun), (0, 60));
    expect(it.days[1].items.first.timeLabel(sun), 'All day');
  });

  test('cost per person adds up price ranges', () {
    expect(Itinerary.costLabel(Itinerary.costOf(it.days[0].items)), 'SGD 15–50');
    expect(Itinerary.costLabel(Itinerary.costOf(it.days[1].items)), '');
  });

  test('chat text lists each day with times, places and prices', () {
    final text = it.chatText();
    expect(text, startsWith('📅 Crew · Sat 24 – Sun 25 Oct 2026'));
    expect(text, contains('*Sat 24 Oct*\n• 10:00 AM – 12:30 PM from activity — Gardens by the Bay, Singapore (SGD 0–20)'));
    expect(text, contains('*Sun 25 Oct*\n• All day Beach day'));
    expect(text, isNot(contains('Someday')));
  });

  test('Excel: a summary sheet, then one sheet per day with plans', () {
    final book = Excel.decodeBytes(it.toExcel());
    expect(book.tables.keys, ['Summary', 'Sat 24 Oct', 'Sun 25 Oct']);
    final day = book.tables['Sat 24 Oct']!;
    expect(day.rows[1].map((c) => c?.value.toString()).take(3), ['Time', 'Plan', 'Type']);
    expect(day.rows[2][1]?.value.toString(), 'from activity');
    expect(day.rows[2][4]?.value.toString(), contains('HYPERLINK('));
    final summary = book.tables['Summary']!;
    expect(summary.rows.last.map((c) => c?.value.toString()), ['Total', '4', 'SGD 15–50']);
  });

  test('an empty range says so', () {
    final none = Itinerary.build(groupName: 'Crew', from: sat, to: sat, entries: const [], activities: const []);
    expect(none.isEmpty, isTrue);
    expect(none.chatText(), contains('Nothing planned yet.'));
  });

  test('"This weekend" is the coming Saturday and Sunday, or this one during it', () {
    final tue = DateTime(2026, 10, 20);
    expect(comingWeekend(tue).start, DateTime(2026, 10, 24));
    expect(comingWeekend(tue).end, DateTime(2026, 10, 25));
    expect(comingWeekend(DateTime(2026, 10, 24)).start, DateTime(2026, 10, 24));
    expect(comingWeekend(DateTime(2026, 10, 25)).start, DateTime(2026, 10, 24));
  });

  test('file names are safe and say the dates', () {
    expect(itineraryFileName('Crew', sat, sun, 'xlsx'), 'Crew itinerary 2026-10-24 to 2026-10-25.xlsx');
    expect(itineraryFileName('A/B: "trip"?', sat, sat, 'pdf'), 'A B trip itinerary 2026-10-24.pdf');
    expect(itineraryFileName('///', sat, sat, 'png'), 'EasyPlan itinerary 2026-10-24.png');
  });

  test('the place skips a first part that repeats the plan name', () {
    ItineraryItem item(String title, String? location) => ItineraryItem.from(
        plan('x', title: title, date: sat),
        location == null ? null : shared('ax', title, location: location));
    final gardens = item('Gardens by the Bay', 'Gardens by the Bay, Marina Gardens Drive, Singapore');
    expect(gardens.placeDetail, 'Marina Gardens Drive, Singapore');
    expect(gardens.shortPlace, 'Marina Gardens Drive');
    expect(item('Lunch at Lau Pa Sat', 'Lau Pa Sat, Raffles Quay, Singapore').shortPlace, 'Raffles Quay');
    expect(item('Kayaking', 'Pasir Ris Park, Singapore').placeDetail, 'Pasir Ris Park, Singapore');
    expect(item('Gardens by the Bay', 'Gardens by the Bay').placeDetail, isNull);
    expect(item('Beach day', null).placeDetail, isNull);
  });
}
