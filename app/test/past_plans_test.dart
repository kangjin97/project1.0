import 'package:flutter_test/flutter_test.dart';
import 'package:group_planner/data/app_clock.dart';
import 'package:group_planner/data/schedule_models.dart';
import 'package:group_planner/features/schedule/schedule_widgets.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

ScheduleEntry entry({bool allDay = false, DateTime? date, DateTime? start, DateTime? end}) => ScheduleEntry(
      id: 'e1',
      groupId: 'g1',
      groupName: 'Crew',
      title: 'Picnic',
      allDay: allDay,
      date: date,
      startAt: start,
      endAt: end,
    );

void main() {
  setUpAll(() {
    tzdata.initializeTimeZones();
    AppClock.use('Asia/Singapore');
  });

  group('isPastAt', () {
    // Set per test: the zone is only chosen once setUpAll has run.
    late DateTime now;
    setUp(() => now = AppClock.at(2026, 10, 15, 14, 0));

    test('an all-day plan is over once its day is behind us', () {
      expect(entry(allDay: true, date: DateTime(2026, 10, 14)).isPastAt(now), isTrue);
      expect(entry(allDay: true, date: DateTime(2026, 10, 15)).isPastAt(now), isFalse, reason: 'still today');
      expect(entry(allDay: true, date: DateTime(2026, 10, 16)).isPastAt(now), isFalse);
    });

    test('a timed plan is over once it has ended, even earlier today', () {
      expect(entry(start: AppClock.at(2026, 10, 15, 9, 0), end: AppClock.at(2026, 10, 15, 11, 0)).isPastAt(now), isTrue);
      expect(entry(start: AppClock.at(2026, 10, 15, 13, 0), end: AppClock.at(2026, 10, 15, 15, 0)).isPastAt(now), isFalse,
          reason: 'happening now');
      expect(entry(start: AppClock.at(2026, 10, 15, 12, 0), end: now).isPastAt(now), isTrue, reason: 'ends right now');
    });

    test('"no date yet" plans are never past', () {
      expect(entry().isPastAt(now), isFalse);
    });
  });

  group('dayHeading', () {
    test('names yesterday, today and tomorrow', () {
      final today = AppClock.today();
      expect(dayHeading(today), startsWith('Today · '));
      expect(dayHeading(addDays(today, 1)), startsWith('Tomorrow · '));
      expect(dayHeading(addDays(today, -1)), startsWith('Yesterday · '));
    });

    test('shows the year only for other years', () {
      final today = AppClock.today();
      final thisYear = DateTime(today.year, 1, 1);
      expect(dayHeading(thisYear), isNot(contains('${today.year}')));
      expect(dayHeading(DateTime(today.year - 1, 6, 1)), endsWith('${today.year - 1}'));
    });
  });
}
