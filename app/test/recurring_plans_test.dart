import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:group_planner/data/models.dart';
import 'package:group_planner/data/schedule_models.dart';
import 'package:group_planner/features/groups/group_history_page.dart';
import 'package:group_planner/features/notifications/notifications_page.dart';
import 'package:group_planner/features/schedule/schedule_widgets.dart';

ScheduleEntry plan({String? seriesId}) => ScheduleEntry(
      id: 'e1',
      groupId: 'g1',
      groupName: 'Crew',
      title: 'Game night',
      allDay: false,
      startAt: DateTime(2026, 10, 16, 19),
      endAt: DateTime(2026, 10, 16, 21),
      seriesId: seriesId,
      seriesFreq: seriesId == null ? null : RepeatFreq.weekly,
      seriesUntil: seriesId == null ? null : DateTime(2026, 11, 6),
    );

void main() {
  test('repeat labels', () {
    expect(repeatLabel(RepeatFreq.weekly, DateTime(2026, 11, 6), thisYear: 2026), 'Repeats weekly until 6 Nov');
    expect(repeatLabel(RepeatFreq.biweekly, DateTime(2027, 1, 31), thisYear: 2026),
        'Repeats every 2 weeks until 31 Jan 2027');
    expect(repeatLabel(RepeatFreq.monthly, DateTime(2026, 12, 15), thisYear: 2026), 'Repeats monthly until 15 Dec');
    expect(RepeatFreq.fromDb('biweekly'), RepeatFreq.biweekly);
    expect(RepeatFreq.fromDb(null), isNull);
  });

  test('being added to a repeating plan is one notification that says how it repeats', () {
    final n = AppNotification(
      id: 'n1',
      kind: 'added_to_series',
      createdAt: DateTime(2026, 10, 15),
      actorName: 'ann',
      groupName: 'Crew',
      entryId: 'e1',
      entryTitle: 'Game night',
      clashCount: 2,
      seriesFreq: RepeatFreq.weekly,
      seriesUntil: DateTime(2026, 11, 6),
    );
    final t = describeNotification(n);
    expect(t.title, 'ann added you to Game night');
    expect(t.detail, startsWith('Repeats weekly until 6 Nov'));
    expect(t.detail, endsWith('Crew · clashes 2 times'));
    expect(n.isAboutPlan, isTrue, reason: 'tapping opens the first date');
  });

  test('one history line for an action across a series says how many dates', () {
    ChangeEntry e(int count) => ChangeEntry(
          entityType: 'schedule_entry',
          action: 'created',
          actorUsername: 'ann',
          createdAt: DateTime(2026, 10, 15),
          subjectName: 'Game night',
          after: const {'title': 'Game night'},
          repeatCount: count,
        );
    expect(describeGroupChange(e(1)), isNot(contains('dates')));
    expect(describeGroupChange(e(4)), endsWith(' · on 4 dates'));
  });

  testWidgets('only repeating plans ask "this date or later dates"', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    })));

    expect(await chooseScope(ctx, plan(), 'Change time'), EditScope.one, reason: 'no question for a single plan');

    final answer = chooseScope(ctx, plan(seriesId: 's1'), 'Change time');
    await tester.pumpAndSettle();
    expect(find.text('This date only'), findsOneWidget);
    await tester.tap(find.text('This and later dates'));
    await tester.pumpAndSettle();
    expect(await answer, EditScope.following);
  });
}
