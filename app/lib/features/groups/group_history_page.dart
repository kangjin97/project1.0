import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/app_clock.dart';
import '../../data/groups_repository.dart';
import '../../data/models.dart';
import '../../data/schedule_models.dart';
import '../../data/schedule_repository.dart';
import '../../widgets/async_body.dart';
import '../../widgets/dialogs.dart';
import '../activities/activity_detail_page.dart';
import '../schedule/entry_detail_sheet.dart';
import '../schedule/schedule_widgets.dart';

/// Who did what in a group, newest first (#8). Opened from the group's menu.
class GroupHistoryPage extends ConsumerStatefulWidget {
  const GroupHistoryPage({super.key, required this.groupId});

  final String groupId;

  @override
  ConsumerState<GroupHistoryPage> createState() => _GroupHistoryPageState();
}

class _GroupHistoryPageState extends ConsumerState<GroupHistoryPage> {
  // Pages after the first, which comes from groupHistoryProvider.
  final _more = <ChangeEntry>[];
  bool _loadingMore = false;

  /// Whether the last page loaded was full, so there may be older entries.
  /// Null until a page beyond the first has loaded.
  bool? _lastPageFull;

  Future<void> _refresh() async {
    setState(() {
      _more.clear();
      _lastPageFull = null;
    });
    ref.invalidate(groupHistoryProvider(widget.groupId));
    await ref.read(groupHistoryProvider(widget.groupId).future);
  }

  Future<void> _loadMore(int beforeId) async {
    setState(() => _loadingMore = true);
    try {
      final page = await ref.read(groupsRepositoryProvider).history(widget.groupId, beforeId: beforeId);
      if (!mounted) return;
      setState(() {
        _more.addAll(page);
        _lastPageFull = page.length == historyPageSize;
      });
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  void initState() {
    super.initState();
    // A live update re-fetches the first page, which then overlaps the older
    // pages loaded so far; drop those so the list has no gap or repeats.
    ref.listenManual(groupHistoryProvider(widget.groupId), (previous, next) {
      if (previous?.hasValue == true && next.hasValue && _more.isNotEmpty) {
        setState(() {
          _more.clear();
          _lastPageFull = null;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(timezoneProvider);
    final groupName = ref.watch(groupProvider(widget.groupId)).value?.name;
    return Scaffold(
      appBar: AppBar(title: Text(groupName == null ? 'History' : '$groupName · History')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: AsyncBody(
          value: ref.watch(groupHistoryProvider(widget.groupId)),
          builder: (first) {
            if (first.isEmpty) {
              return ListView(children: const [
                EmptyState(icon: Icons.history, message: 'Nothing has happened in this group yet.'),
              ]);
            }
            final entries = [...first, ..._more];
            final hasMore = _lastPageFull ?? first.length == historyPageSize;
            return ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                ..._withDayHeadings(context, entries),
                if (hasMore)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: _loadingMore
                          ? const CircularProgressIndicator()
                          : OutlinedButton(
                              onPressed: () => _loadMore(entries.last.id!),
                              child: const Text('Show older'),
                            ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  List<Widget> _withDayHeadings(BuildContext context, List<ChangeEntry> entries) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final children = <Widget>[];
    DateTime? day;
    for (final e in entries) {
      final at = AppClock.inZone(e.createdAt);
      if (day == null || !isSameDay(day, at)) {
        day = dateOnly(at);
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(historyDayHeading(day),
              style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
        ));
      }
      final open = _opener(e);
      children.add(ListTile(
        dense: true,
        leading: Icon(_icon(e), size: 20),
        title: Text('${e.actorUsername == null ? 'A deleted user' : '@${e.actorUsername}'} ${describeGroupChange(e)}'),
        subtitle: Text(formatTime(at), style: muted),
        trailing: open == null ? null : const Icon(Icons.chevron_right, size: 20),
        onTap: open,
      ));
    }
    return children;
  }

  /// What tapping a line opens: the activity, the plan or the member, while
  /// they still exist and are visible. Null when there's nothing to open.
  VoidCallback? _opener(ChangeEntry e) {
    final id = e.entityId;
    switch (e.entityType) {
      // subject_name is only set while the caller can still see the activity.
      case 'activity' || 'activity_photo' || 'group_activity' when id != null && e.subjectName != null:
        return () => context.push('/activities/$id');
      case 'schedule_entry' || 'schedule_participant' when e.entryId != null:
        return () => showEntryDetail(
            context,
            queryAroundEntry(groupId: widget.groupId, date: e.entryDate, start: e.entryStartAt, end: e.entryEndAt),
            e.entryId!);
      case 'group_member' when id != null && e.personUsername != null:
        return () => context.push('/people/$id');
      default:
        return null;
    }
  }

  IconData _icon(ChangeEntry e) => switch (e.entityType) {
        'activity' || 'activity_photo' => Icons.edit_outlined,
        'group_activity' => Icons.local_activity_outlined,
        'activity_type' || 'type_merge' => Icons.label_outline,
        'schedule_entry' => Icons.event_outlined,
        'schedule_participant' => Icons.person_outline,
        'group_member' => Icons.group_outlined,
        'invite_link' => Icons.link,
        'invitation' => Icons.mail_outline,
        _ => Icons.history,
      };
}

/// "Today", "Yesterday", or e.g. "Saturday, 12 October".
String historyDayHeading(DateTime day) {
  final today = AppClock.today();
  if (isSameDay(day, today)) return 'Today';
  if (isSameDay(day, addDays(today, -1))) return 'Yesterday';
  return DateFormat(day.year == today.year ? 'EEEE, d MMMM' : 'EEEE, d MMMM y').format(day);
}

/// Plain-language summary of a group history entry, after the actor's name.
/// Names that are gone (deleted, or no longer visible) read as "an activity",
/// "a plan", "a deleted user" and so on.
String describeGroupChange(ChangeEntry e) {
  String q(String s) => '“$s”';
  final activity = e.subjectName == null ? 'an activity' : q(e.subjectName!);
  final plan = e.subjectName == null ? 'a plan' : q(e.subjectName!);
  final person = e.personUsername == null ? 'a deleted user' : '@${e.personUsername}';
  final from = e.fromTypeName;
  final to = e.toTypeName;

  // Joining or leaving yourself vs. someone else adding or removing you.
  // Compared by id so it still works once the account is deleted.
  final personId = switch (e.entityType) {
    'group_member' => e.entityId,
    'schedule_participant' => (e.after ?? e.before)?['user_id'] as String?,
    _ => null,
  };
  final self = personId != null && personId == e.actorId;

  switch ((e.entityType, e.action)) {
    case ('activity', 'updated'):
      final change = describeChange(e, const {});
      return change.startsWith('changed ') ? '$change on $activity' : 'edited $activity';
    case ('activity_photo', 'created'):
      return 'added a photo to $activity';
    case ('activity_photo', 'deleted'):
      return 'removed a photo from $activity';

    case ('group_activity', 'created'):
      return to == null ? 'shared $activity' : 'shared $activity under $to';
    case ('group_activity', 'deleted'):
      return 'removed $activity from the group';
    case ('group_activity', 'type_changed'):
      if (from != null && to != null) return 'moved $activity from $from to $to';
      if (to != null) return 'moved $activity to $to';
      if (from != null) return 'moved $activity out of $from';
      return 'changed the type of $activity';

    case ('activity_type', 'created'):
      return 'added the type ${q(e.subjectName ?? '')}';
    case ('activity_type', 'updated'):
      final old = e.before?['name'] as String?;
      return old == null ? 'renamed a type to ${q(e.subjectName ?? '')}' : 'renamed the type ${q(old)} to ${q(e.subjectName ?? '')}';
    case ('activity_type', 'deleted'):
      return 'deleted the type ${q(e.subjectName ?? '')}';
    case ('type_merge', 'created' || 'updated'):
      return 'merged ${q(e.subjectName ?? '')} into ${to ?? 'another type'}';
    case ('type_merge', 'deleted'):
      return 'undid the merge of ${q(e.subjectName ?? '')}';

    case ('schedule_entry', 'created'):
      // An event is named as it was then; an activity may have replaced it since.
      final title = e.after?['title'] as String?;
      if (e.after?['activity_id'] != null) return 'planned $plan';
      return 'planned the event ${title == null ? plan : q(title)}';
    case ('schedule_entry', 'deleted'):
      return 'removed $plan from the schedule';
    case ('schedule_entry', 'updated'):
      final keys = (e.after ?? const {}).keys.toSet();
      if (keys.intersection({'date', 'start_at', 'end_at', 'all_day'}).isNotEmpty) return 'changed the time of $plan';
      if (keys.contains('title')) {
        final old = e.before?['title'] as String?;
        return old == null ? 'renamed $plan' : 'renamed the event ${q(old)} to $plan';
      }
      return 'edited $plan';
    case ('schedule_entry', 'event_replaced'):
      final event = e.eventTitle;
      return event == null ? 'replaced an event with $plan' : 'replaced the event ${q(event)} with $plan';
    case ('schedule_entry', 'activity_swapped'):
      return 'swapped in $plan for a plan’s activity';
    case ('schedule_entry', 'reverted_to_event'):
      return 'turned $plan back into an event';
    case ('schedule_entry', 'clash_override'):
      final clashes = e.after?['clashes'] as List? ?? const [];
      final people = {for (final c in clashes) '@${(c as Map)['username']}'};
      return 'went ahead with $plan despite clashes for ${people.join(', ')}';

    case ('schedule_participant', 'created'):
      return self ? 'joined $plan' : 'added $person to $plan';
    case ('schedule_participant', 'deleted'):
      return self ? 'left $plan' : 'removed $person from $plan';
    // The log doesn't say whose status it was: the participant keeping both
    // plans, or a planner's reschedule that ended the clash.
    case ('schedule_participant', 'updated'):
      return 'cleared a clash on $plan';

    case ('invite_link', 'created'):
      return 'created an invite link';
    case ('invite_link', 'updated'):
      return 'revoked an invite link';
    case ('invitation', 'created'):
      return 'invited $person';
    case ('invitation', 'updated'):
      return switch (e.after?['status']) {
        'declined' => 'declined the invitation',
        'cancelled' => 'cancelled the invitation for $person',
        _ => 'updated the invitation for $person',
      };

    case ('group_member', 'created'):
      if (e.after?['role'] == 'owner') return 'created the group';
      return self ? 'joined the group' : 'added $person to the group';
    case ('group_member', 'deleted'):
      return self ? 'left the group' : 'removed $person from the group';

    default:
      return '${e.action.replaceAll('_', ' ')} (${e.entityType.replaceAll('_', ' ')})';
  }
}
