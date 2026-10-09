import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/activities_repository.dart';
import '../../data/app_clock.dart';
import '../../data/groups_repository.dart';
import '../../data/models.dart';
import '../../data/schedule_models.dart';
import '../../data/schedule_repository.dart';
import '../../widgets/async_body.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/user_avatar.dart';
import 'entry_editor.dart';
import 'schedule_widgets.dart';

/// Details and actions for one entry. [query] is the list it was opened
/// from, so the sheet stays in sync as the entry changes.
Future<void> showEntryDetail(BuildContext context, ScheduleQuery query, String entryId) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (_, controller) => _EntryDetail(query: query, entryId: entryId, controller: controller),
    ),
  );
}

class _EntryDetail extends ConsumerWidget {
  const _EntryDetail({required this.query, required this.entryId, required this.controller});

  final ScheduleQuery query;
  final String entryId;
  final ScrollController controller;

  Future<void> _run(BuildContext context, WidgetRef ref, Future<void> Function() action, {String? done}) async {
    try {
      await action();
      invalidateSchedule(ref);
      if (done != null && context.mounted) showMessage(context, done);
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _addPeople(BuildContext context, WidgetRef ref, ScheduleEntry e) async {
    final members = await ref.read(membersProvider(e.groupId).future);
    final inEntry = {for (final p in e.participants) p.userId};
    final candidates = members.where((m) => !inEntry.contains(m.profile.id)).toList();
    if (!context.mounted) return;
    if (candidates.isEmpty) {
      showMessage(context, 'Everyone in ${e.groupName} is already in this.');
      return;
    }
    final picked = await showDialog<Set<String>>(
      context: context,
      builder: (_) => _PickPeopleDialog(members: candidates),
    );
    if (picked == null || picked.isEmpty || !context.mounted) return;

    final repo = ref.read(scheduleRepositoryProvider);
    try {
      var result = await repo.addParticipants(e.id, picked.toList());
      if (!result.saved) {
        if (!context.mounted) return;
        if (!await confirmClashes(context, result.clashes)) return;
        result = await repo.addParticipants(e.id, picked.toList(), force: true);
      }
      invalidateSchedule(ref);
    } catch (err) {
      if (context.mounted) showError(context, err);
    }
  }

  Future<void> _pickActivity(BuildContext context, WidgetRef ref, ScheduleEntry e) async {
    final activities = await ref.read(groupActivitiesProvider(e.groupId).future);
    final options = activities.where((a) => a.activityId != e.activityId).toList();
    if (!context.mounted) return;
    if (options.isEmpty) {
      showMessage(context, 'No other activities in ${e.groupName} yet.');
      return;
    }
    final picked = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(e.isEvent ? 'Replace “${e.displayTitle}” with…' : 'Swap for…'),
        children: [
          for (final ga in options)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, ga.activityId),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(ga.activity.name),
                subtitle: Text([if (ga.typeName != null) ga.typeName!, if (ga.activity.priceLabel != null) ga.activity.priceLabel!].join(' · ')),
              ),
            ),
        ],
      ),
    );
    if (picked == null || !context.mounted) return;
    await _run(context, ref, () => ref.read(scheduleRepositoryProvider).setActivity(e.id, picked),
        done: e.isEvent ? 'Event replaced' : 'Activity swapped');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(scheduleProvider(query));
    final e = list.value?.where((x) => x.id == entryId).firstOrNull;
    final theme = Theme.of(context);
    final repo = ref.read(scheduleRepositoryProvider);

    if (e == null) {
      return list.isLoading
          ? const Center(child: CircularProgressIndicator())
          : const EmptyState(icon: Icons.event_busy_outlined, message: 'This plan is no longer on this schedule.');
    }

    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      children: [
        Row(
          children: [
            if (e.isEvent) ...[
              Icon(Icons.lightbulb_outline, color: theme.colorScheme.tertiary),
              const SizedBox(width: 8),
            ],
            Expanded(child: Text(e.displayTitle, style: theme.textTheme.headlineSmall)),
          ],
        ),
        const SizedBox(height: 4),
        Text([e.groupName, if (e.isEvent) 'Event'].join(' · '), style: theme.textTheme.bodyMedium),
        const SizedBox(height: 12),
        Row(
          children: [
            const Icon(Icons.schedule, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(whenLabel(e), style: theme.textTheme.bodyLarge)),
          ],
        ),
        if (e.iHaveClash) ...[
          const SizedBox(height: 12),
          Card(
            color: theme.colorScheme.errorContainer,
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('This overlaps with something else on your schedule.',
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onErrorContainer)),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => _run(context, ref, () => repo.leave(e.id), done: 'You left this plan'),
                        child: const Text('Leave this'),
                      ),
                      TextButton(
                        onPressed: () => _run(context, ref, () => repo.acknowledgeClash(e.id), done: 'Kept both'),
                        child: const Text('Keep both'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.tonalIcon(
              onPressed: () => showRescheduleEditor(context, e),
              icon: const Icon(Icons.edit_calendar_outlined),
              label: const Text('Change time'),
            ),
            FilledButton.tonalIcon(
              onPressed: () => _addPeople(context, ref, e),
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Add people'),
            ),
            FilledButton.tonalIcon(
              onPressed: () => _pickActivity(context, ref, e),
              icon: const Icon(Icons.swap_horiz),
              label: Text(e.isEvent ? 'Replace with activity' : 'Swap activity'),
            ),
            if (e.isEvent)
              OutlinedButton.icon(
                onPressed: () async {
                  final name = await promptText(context,
                      title: 'Rename event', label: 'Event name', action: 'Save', initial: e.title ?? '');
                  if (name == null || name.trim().isEmpty || !context.mounted) return;
                  await _run(context, ref, () => repo.rename(e.id, name));
                },
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Rename'),
              ),
            if (e.activityId != null)
              OutlinedButton.icon(
                onPressed: () {
                  // The sheet's context is gone once it closes; grab the router first.
                  final router = GoRouter.of(context);
                  Navigator.pop(context);
                  router.push('/activities/${e.activityId}');
                },
                icon: const Icon(Icons.open_in_new),
                label: const Text('View activity'),
              ),
          ],
        ),
        const Divider(height: 32),
        Text('Going (${e.participants.length})', style: theme.textTheme.titleMedium),
        for (final p in e.participants)
          ListTile(
            contentPadding: EdgeInsets.zero,
            onTap: () {
              // The sheet's context is gone once it closes; grab the router first.
              final router = GoRouter.of(context);
              final me = Supabase.instance.client.auth.currentUser?.id;
              Navigator.pop(context);
              router.push(p.userId == me ? '/profile' : '/people/${p.userId}');
            },
            leading: UserAvatar(label: p.label, avatarPath: p.avatarPath),
            title: Text(p.label),
            subtitle: Text('@${p.username}'),
            trailing: p.hasClash
                ? Tooltip(
                    message: 'Has something else at this time',
                    child: Chip(
                      avatar: Icon(Icons.warning_amber_rounded, size: 16, color: theme.colorScheme.error),
                      label: const Text('Clash'),
                    ),
                  )
                : null,
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            if (e.iAmIn)
              OutlinedButton(
                onPressed: () async {
                  final ok = await confirm(context,
                      title: 'Leave this plan?',
                      message: 'It comes off your schedule. Others keep it.',
                      action: 'Leave');
                  if (ok && context.mounted) await _run(context, ref, () => repo.leave(e.id), done: 'You left this plan');
                },
                child: const Text('Leave'),
              ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
              onPressed: () async {
                final ok = await confirm(context,
                    title: 'Remove from the schedule?',
                    message: 'It’s removed for everyone in ${e.groupName}.',
                    action: 'Remove');
                if (!ok || !context.mounted) return;
                await _run(context, ref, () => repo.delete(e.id), done: 'Removed from the schedule');
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Remove for everyone'),
            ),
          ],
        ),
        const Divider(height: 32),
        Text('History', style: theme.textTheme.titleMedium),
        _History(entry: e),
      ],
    );
  }
}

class _History extends ConsumerWidget {
  const _History({required this.entry});

  final ScheduleEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(timezoneProvider);
    final members = ref.watch(membersProvider(entry.groupId)).value ?? const <Member>[];
    final names = {
      for (final m in members) m.profile.id: m.profile.username,
      for (final p in entry.participants) p.userId: p.username,
    };
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return AsyncBody(
      value: ref.watch(entryHistoryProvider(entry.id)),
      builder: (entries) => Column(
        children: [
          for (final h in entries)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.history, size: 20),
              title: Text('@${h.actorUsername ?? 'someone'} ${describeEntryChange(h, names)}'),
              subtitle: Text(DateFormat('d MMM y, h:mm a').format(AppClock.inZone(h.createdAt)), style: muted),
            ),
        ],
      ),
    );
  }
}

/// Plain-language summary of a change-log entry about a schedule entry.
String describeEntryChange(ChangeEntry e, Map<String, String> usernames) {
  String who(Map<String, dynamic>? row) {
    final id = row?['user_id'] as String?;
    return '@${usernames[id] ?? 'someone'}';
  }

  switch ((e.entityType, e.action)) {
    case ('schedule_entry', 'created'):
      return e.after?['activity_id'] == null ? 'planned this event' : 'planned this';
    case ('schedule_entry', 'event_replaced'):
      return 'replaced the event with an activity';
    case ('schedule_entry', 'activity_swapped'):
      return 'swapped in a different activity';
    case ('schedule_entry', 'reverted_to_event'):
      return 'turned it back into an event (the activity was removed)';
    case ('schedule_entry', 'clash_override'):
      final clashes = (e.after?['clashes'] as List? ?? const []);
      final people = {for (final c in clashes) '@${(c as Map)['username']}'};
      return 'went ahead despite clashes for ${people.join(', ')}';
    case ('schedule_entry', 'updated'):
      final keys = (e.after ?? const {}).keys.toSet();
      if (keys.intersection({'date', 'start_at', 'end_at', 'all_day'}).isNotEmpty) return 'changed the time';
      if (keys.contains('title')) return 'renamed it to “${e.after?['title']}”';
      return 'edited it';
    case ('schedule_participant', 'created'):
      return 'added ${who(e.after)}';
    case ('schedule_participant', 'deleted'):
      final left = who(e.before);
      return left == '@${e.actorUsername}' ? 'left' : 'removed $left';
    case ('schedule_participant', 'updated'):
      return e.after?['status'] == 'added' ? 'kept it despite a clash' : 'was marked as clashing';
    default:
      return e.action.replaceAll('_', ' ');
  }
}

class _PickPeopleDialog extends StatefulWidget {
  const _PickPeopleDialog({required this.members});

  final List<Member> members;

  @override
  State<_PickPeopleDialog> createState() => _PickPeopleDialogState();
}

class _PickPeopleDialogState extends State<_PickPeopleDialog> {
  final _picked = <String>{};

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Add people'),
        content: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final m in widget.members)
              FilterChip(
                label: Text(m.profile.label),
                selected: _picked.contains(m.profile.id),
                onSelected: (on) => setState(() => on ? _picked.add(m.profile.id) : _picked.remove(m.profile.id)),
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, _picked), child: const Text('Add')),
        ],
      );
}
