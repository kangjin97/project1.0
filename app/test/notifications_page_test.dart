import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:group_planner/data/models.dart';
import 'package:group_planner/data/notifications_repository.dart';
import 'package:group_planner/features/notifications/notifications_page.dart';

/// Stands in for the server: marking read sets read_at on what it returns next.
class _FakeRepo extends NotificationsRepository {
  _FakeRepo(this.rows);

  List<AppNotification> rows;
  int marks = 0;

  @override
  Future<List<AppNotification>> list({int limit = 50}) async => rows;

  @override
  Future<int> unreadCount() async => rows.where((n) => n.unread).length;

  @override
  Future<void> markAllRead() async {
    marks++;
    rows = [for (final n in rows) n.unread ? _read(n) : n];
  }
}

AppNotification _note(String id, {DateTime? readAt}) => AppNotification(
      id: id,
      kind: 'group_deleted',
      createdAt: DateTime.utc(2026, 10, 15, 9),
      readAt: readAt,
      actorName: 'bob',
      groupName: 'Crew $id',
    );

AppNotification _read(AppNotification n) => _note(n.id, readAt: DateTime.utc(2026, 10, 15, 10));

void main() {
  testWidgets('unread items stay highlighted for the visit after the list refetches as read', (tester) async {
    final repo = _FakeRepo([_note('a'), _note('b', readAt: DateTime.utc(2026, 10, 14))]);
    await tester.pumpWidget(ProviderScope(
      overrides: [notificationsRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: NotificationsPage()),
    ));
    await tester.pumpAndSettle();

    expect(repo.marks, 1, reason: 'opening the page marks them read');
    expect(find.byKey(const ValueKey('unread-dot')), findsOneWidget);

    // Live updates: marking read broadcasts a change and the list refetches.
    ProviderScope.containerOf(tester.element(find.byType(NotificationsPage))).invalidate(notificationsProvider);
    await tester.pumpAndSettle();

    expect(repo.rows.every((n) => !n.unread), isTrue, reason: 'the refetched list is all read');
    expect(find.byKey(const ValueKey('unread-dot')), findsOneWidget, reason: 'the one that was new keeps its dot');
    expect(repo.marks, 1, reason: 'nothing left to mark');
  });

  testWidgets('a notification arriving while the page is open is highlighted and marked read', (tester) async {
    final repo = _FakeRepo([_note('a', readAt: DateTime.utc(2026, 10, 14))]);
    await tester.pumpWidget(ProviderScope(
      overrides: [notificationsRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: NotificationsPage()),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('unread-dot')), findsNothing);
    expect(repo.marks, 0);

    repo.rows = [_note('new'), ...repo.rows];
    final container = ProviderScope.containerOf(tester.element(find.byType(NotificationsPage)));
    container.invalidate(notificationsProvider);
    await tester.pumpAndSettle();
    container.invalidate(notificationsProvider); // the refetch after marking read
    await tester.pumpAndSettle();

    expect(repo.marks, 1);
    expect(find.byKey(const ValueKey('unread-dot')), findsOneWidget);
  });
}
