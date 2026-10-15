import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:group_planner/data/app_clock.dart';
import 'package:group_planner/data/schedule_models.dart';
import 'package:group_planner/features/schedule/calendar_views.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

// 48 px per hour in the week view.
const hour = 48.0;

ScheduleEntry plan(DateTime start, DateTime end) => ScheduleEntry(
      id: 'e1',
      groupId: 'g1',
      groupName: 'Crew',
      title: 'Dinner',
      allDay: false,
      startAt: start,
      endAt: end,
      myStatus: 'added',
    );

Future<void> pumpWeek(WidgetTester tester, {required Size size, required List<ScheduleEntry> entries,
    required void Function(ScheduleEntry, DateTime) onMove}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: WeekView(
        weekStart: DateTime(2026, 10, 19), // a Monday
        entries: entries,
        onTap: (_) {},
        onTapDay: (_) {},
        onMove: onMove,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    tzdata.initializeTimeZones();
    AppClock.use('UTC');
  });

  group('dropStart', () {
    final day = AppClock.at(2026, 10, 20);
    // Same moment; the time zone objects can differ.
    Matcher at(DateTime t) => predicate<DateTime>((d) => d.isAtSameMomentAs(t), '$t');

    test('snaps to 15 minutes', () {
      expect(dropStart(day, 19 * hour), at(AppClock.at(2026, 10, 20, 19)));
      expect(dropStart(day, 19 * hour + hour / 4 + 3), at(AppClock.at(2026, 10, 20, 19, 15)));
      expect(dropStart(day, 19 * hour + hour / 8 - 1), at(AppClock.at(2026, 10, 20, 19)));
    });

    test('stays within the day', () {
      expect(dropStart(day, -30), at(day));
      expect(dropStart(day, 30 * hour), at(AppClock.at(2026, 10, 20, 23, 45)));
    });
  });

  testWidgets('dragging a plan down two hours on a wide screen moves its start', (tester) async {
    final moves = <(ScheduleEntry, DateTime)>[];
    final start = AppClock.at(2026, 10, 21, 10), end = AppClock.at(2026, 10, 21, 11, 30);
    await pumpWeek(tester, size: const Size(1200, 900), entries: [plan(start, end)], onMove: (e, s) => moves.add((e, s)));

    final block = find.textContaining('Dinner');
    expect(block, findsOneWidget);
    await tester.drag(block, const Offset(0, 2 * hour));
    await tester.pumpAndSettle();

    expect(moves, hasLength(1));
    expect(moves.single.$2, AppClock.at(2026, 10, 21, 12));
  });

  testWidgets('dragging to the next day keeps the time', (tester) async {
    final moves = <DateTime>[];
    final start = AppClock.at(2026, 10, 21, 10), end = AppClock.at(2026, 10, 21, 11);
    await pumpWeek(tester, size: const Size(1200, 900), entries: [plan(start, end)], onMove: (_, s) => moves.add(s));

    // Seven equal day columns after the 56 px hour gutter.
    const column = (1200 - 56) / 7;
    await tester.drag(find.textContaining('Dinner'), const Offset(column, 0));
    await tester.pumpAndSettle();

    expect(moves, [AppClock.at(2026, 10, 22, 10)]);
  });

  testWidgets('a tiny drag that lands on the same time does nothing', (tester) async {
    final moves = <DateTime>[];
    final start = AppClock.at(2026, 10, 21, 10), end = AppClock.at(2026, 10, 21, 11);
    await pumpWeek(tester, size: const Size(1200, 900), entries: [plan(start, end)], onMove: (_, s) => moves.add(s));

    await tester.drag(find.textContaining('Dinner'), const Offset(0, 4));
    await tester.pumpAndSettle();

    expect(moves, isEmpty);
  });

  testWidgets('phones can\'t drag (tap → Change time instead)', (tester) async {
    final start = AppClock.at(2026, 10, 21, 10), end = AppClock.at(2026, 10, 21, 11);
    await pumpWeek(tester, size: const Size(400, 800), entries: [plan(start, end)], onMove: (_, _) {});
    expect(find.byType(Draggable<ScheduleEntry>), findsNothing);
  });
}
