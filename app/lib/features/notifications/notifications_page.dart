import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/app_clock.dart';
import '../../data/models.dart';
import '../../data/notifications_repository.dart';
import '../../data/schedule_models.dart';
import '../../data/schedule_repository.dart';
import '../../widgets/async_body.dart';
import '../../widgets/dialogs.dart';
import '../schedule/entry_detail_sheet.dart';
import '../schedule/schedule_widgets.dart';

/// What a notification says: a headline and an optional detail line.
({String title, String? detail}) describeNotification(AppNotification n) {
  final who = n.actorName ?? 'Someone';
  final plan = n.entryTitle ?? 'a plan';
  final when = planWhen(n);
  switch (n.kind) {
    case 'group_invitation':
      return (
        title: '$who invited you to ${n.groupName ?? 'a group'}',
        detail: switch (n.invitationStatus) {
          'pending' => 'Tap to accept or decline',
          'accepted' => 'You joined',
          'declined' => 'You declined',
          'cancelled' => 'Cancelled',
          _ => null,
        },
      );
    case 'added_to_entry':
      return (title: '$who added you to $plan', detail: [?n.groupName, ?when].join(' · '));
    case 'schedule_clash':
      final clashes = n.clashCount == 1 ? '1 of your plans' : '${n.clashCount} of your plans';
      return (
        title: '${n.entryTitle ?? 'A plan'} clashes with $clashes',
        detail: ['$who added you anyway', ?when].join(' · '),
      );
    case 'added_to_series':
      final repeats = n.seriesFreq == null || n.seriesUntil == null
          ? null
          : repeatLabel(n.seriesFreq!, n.seriesUntil!, thisYear: AppClock.today().year);
      final clashes = n.clashCount == 0 ? null : n.clashCount == 1 ? 'clashes once' : 'clashes ${n.clashCount} times';
      return (title: '$who added you to $plan', detail: [?repeats, ?n.groupName, ?clashes].join(' · '));
    case 'group_deleted':
      return (title: '$who deleted ${n.groupName ?? 'a group'}', detail: 'Its plans were removed from your schedule');
    case 'ownership_transferred':
      return (title: '$who made you the owner of ${n.groupName ?? 'a group'}', detail: null);
    default:
      return (title: 'Notification', detail: null);
  }
}

/// When the plan happens, in the display time zone; null if it's not visible.
String? planWhen(AppNotification n) {
  if (n.entryId == null) return null;
  if (n.entryAllDay && n.entryDate != null) return '${formatShortDay(n.entryDate!)}, all day';
  if (n.entryStartAt != null) return '${formatShortDay(n.entryStartAt!)}, ${formatTime(n.entryStartAt!)}';
  return 'No date yet';
}

/// "Just now", "5 min ago", "3 h ago", "2 d ago", then the date.
String timeAgo(DateTime t, DateTime now) {
  final d = now.difference(t);
  if (d.inMinutes < 1) return 'Just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  if (d.inDays < 7) return '${d.inDays} d ago';
  return DateFormat('d MMM').format(t);
}

class NotificationsPage extends ConsumerStatefulWidget {
  const NotificationsPage({super.key});

  @override
  ConsumerState<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends ConsumerState<NotificationsPage> {
  /// Notifications that were unread when this visit saw them. They stay
  /// highlighted until the page closes, even though marking them read makes
  /// the list refetch (live updates) with `read_at` set.
  final _seenUnread = <String>{};

  @override
  void initState() {
    super.initState();
    // Opening the list marks everything read and the badge clears straight away.
    // New ones arriving while the page is open are treated the same way.
    ref.listenManual(notificationsProvider, (_, next) {
      // While refetching, `value` is still the previous (unread) list.
      if (next.isLoading) return;
      final unread = [for (final n in next.value ?? const <AppNotification>[]) if (n.unread) n.id];
      if (unread.isEmpty) return;
      _seenUnread.addAll(unread);
      _markRead();
    }, fireImmediately: true);
  }

  Future<void> _markRead() async {
    try {
      await ref.read(notificationsRepositoryProvider).markAllRead();
    } catch (_) {
      // The badge just stays until the next try; nothing for the user to do.
    }
    ref.invalidate(unreadCountProvider);
  }

  void _open(AppNotification n) {
    if (n.isInvitation) {
      if (n.invitationStatus == 'cancelled') {
        showMessage(context, 'This invitation was cancelled.');
        return;
      }
      context.go('/groups');
    } else if (n.isAboutPlan) {
      final id = n.entryId;
      if (id == null) {
        showMessage(context, 'You’re no longer in this plan.');
        return;
      }
      showEntryDetail(
          context,
          queryAroundEntry(groupId: n.groupId, date: n.entryDate, start: n.entryStartAt, end: n.entryEndAt),
          id);
    } else if (n.opensGroup) {
      context.go('/groups/${n.groupId}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(notificationsProvider);
          ref.invalidate(unreadCountProvider);
          await ref.read(notificationsProvider.future);
        },
        child: AsyncBody(
          value: ref.watch(notificationsProvider),
          builder: (list) => list.isEmpty
              ? ListView(children: const [
                  EmptyState(
                    icon: Icons.notifications_none,
                    message: 'Nothing yet. Invitations and plans people add you to show up here.',
                  ),
                ])
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 32),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) => _NotificationTile(
                    n: list[i],
                    highlight: list[i].unread || _seenUnread.contains(list[i].id),
                    onTap: () => _open(list[i]),
                  ),
                ),
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.n, required this.highlight, required this.onTap});

  final AppNotification n;

  /// Shown as new: unread now, or unread when this visit started.
  final bool highlight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = describeNotification(n);
    final (icon, color) = switch (n.kind) {
      'group_invitation' => (Icons.group_add_outlined, theme.colorScheme.primary),
      'schedule_clash' => (Icons.warning_amber_rounded, theme.colorScheme.error),
      'added_to_series' => (Icons.event_repeat_outlined, theme.colorScheme.primary),
      'group_deleted' => (Icons.group_off_outlined, theme.colorScheme.error),
      'ownership_transferred' => (Icons.workspace_premium_outlined, theme.colorScheme.primary),
      _ => (Icons.event_available_outlined, theme.colorScheme.primary),
    };
    return ListTile(
      tileColor: highlight ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35) : null,
      leading: Icon(icon, color: color),
      title: Text(text.title, style: highlight ? const TextStyle(fontWeight: FontWeight.w600) : null),
      subtitle: Text([?text.detail, timeAgo(n.createdAt, AppClock.now())].where((s) => s.isNotEmpty).join(' · ')),
      trailing: highlight
          ? Container(
              key: const ValueKey('unread-dot'),
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: theme.colorScheme.primary, shape: BoxShape.circle),
            )
          : null,
      onTap: n.isInvitation || n.isAboutPlan || n.opensGroup ? onTap : null,
    );
  }
}
