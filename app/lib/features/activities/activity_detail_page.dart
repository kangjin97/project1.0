import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/activities_repository.dart';
import '../../data/groups_repository.dart';
import '../../data/models.dart';
import '../../widgets/async_body.dart';
import '../../widgets/dialogs.dart';
import 'activity_form_page.dart';
import 'activity_widgets.dart';
import 'share_activity_sheet.dart';

class ActivityDetailPage extends ConsumerWidget {
  const ActivityDetailPage({super.key, required this.activityId});

  final String activityId;

  Future<void> _delete(BuildContext context, WidgetRef ref, Activity a) async {
    final ok = await confirm(
      context,
      title: 'Delete ${a.name}?',
      message: 'It will be removed from every group. Plans that used it stay on schedules as events.',
      action: 'Delete',
    );
    if (!ok || !context.mounted) return;
    try {
      await ref.read(activitiesRepositoryProvider).delete(a.id);
      invalidateActivity(ref, a.id);
      if (context.mounted) {
        context.canPop() ? context.pop() : context.go('/activities');
      }
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = Supabase.instance.client.auth.currentUser!.id;
    final activity = ref.watch(activityProvider(activityId));
    final a = activity.value;
    return Scaffold(
      appBar: AppBar(
        title: Text(a?.name ?? ''),
        actions: [
          if (a != null) ...[
            IconButton(
              tooltip: 'Edit',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => showActivityForm(context, activity: a),
            ),
            if (a.ownerId == me)
              PopupMenuButton<String>(
                onSelected: (_) => _delete(context, ref, a),
                itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('Delete activity'))],
              ),
          ],
        ],
      ),
      body: AsyncBody(
        value: activity,
        builder: (a) => a == null
            ? const EmptyState(icon: Icons.visibility_off_outlined, message: 'This activity was deleted or isn’t shared with you.')
            : _Body(activity: a),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.activity});

  final Activity activity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = activity;
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.only(bottom: 48),
      children: [
        if (a.photos.isNotEmpty)
          SizedBox(
            height: 240,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(16),
              itemCount: a.photos.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) => ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: 4 / 3,
                  child: ActivityPhotoImage(storagePath: a.photos[i].storagePath),
                ),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(a.name, style: theme.textTheme.headlineSmall),
              if (a.description != null) ...[
                const SizedBox(height: 8),
                Text(a.description!, style: theme.textTheme.bodyLarge),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (a.personalTypeName != null)
          ListTile(
            leading: const Icon(Icons.label_outline),
            title: Text(a.personalTypeName!),
            subtitle: const Text('Your label (only you see this)'),
          ),
        if (a.location != null)
          ListTile(
            leading: const Icon(Icons.place_outlined),
            title: Text(a.location!),
            subtitle: const Text('Open in maps'),
            onTap: () => launchUrl(
              Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': a.location!}),
              mode: LaunchMode.externalApplication,
            ),
          ),
        if (a.priceLabel != null)
          ListTile(leading: const Icon(Icons.payments_outlined), title: Text(a.priceLabel!)),
        if (a.url != null)
          ListTile(
            leading: const Icon(Icons.link),
            title: Text(a.url!, maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () {
              final uri = Uri.tryParse(a.url!);
              if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
            },
          ),
        const Divider(height: 32),
        _GroupsSection(activityId: a.id),
        const Divider(height: 32),
        _HistorySection(activityId: a.id),
      ],
    );
  }
}

class _GroupsSection extends ConsumerWidget {
  const _GroupsSection({required this.activityId});

  final String activityId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shared = ref.watch(sharedInProvider(activityId));
    final repo = ref.read(activitiesRepositoryProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(child: Text('Groups', style: Theme.of(context).textTheme.titleMedium)),
              FilledButton.tonalIcon(
                onPressed: () => showShareActivitySheet(context, activityId: activityId),
                icon: const Icon(Icons.group_add_outlined),
                label: const Text('Share to a group'),
              ),
            ],
          ),
        ),
        AsyncBody(
          value: shared,
          builder: (list) => list.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Private: only you can see it until you share it into a group.'),
                )
              : Column(
                  children: [
                    for (final s in list)
                      ListTile(
                        leading: const Icon(Icons.groups_outlined),
                        title: Text(s.groupName),
                        onTap: () => context.go('/groups/${s.groupId}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _TypeMenu(
                              groupId: s.groupId,
                              currentTypeId: s.typeId,
                              currentName: s.typeName ?? 'Type',
                              onChanged: (typeId) async {
                                try {
                                  await repo.changeType(activityId: activityId, groupId: s.groupId, typeId: typeId);
                                  invalidateActivity(ref, activityId, groupId: s.groupId);
                                } catch (e) {
                                  if (context.mounted) showError(context, e);
                                }
                              },
                            ),
                            IconButton(
                              tooltip: 'Remove from ${s.groupName}',
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: () async {
                                final ok = await confirm(context,
                                    title: 'Remove from ${s.groupName}?',
                                    message: 'The activity isn’t deleted. Plans in that group that used it stay as events.',
                                    action: 'Remove');
                                if (!ok) return;
                                try {
                                  await repo.unshare(activityId: activityId, groupId: s.groupId);
                                  invalidateActivity(ref, activityId, groupId: s.groupId);
                                } catch (e) {
                                  if (context.mounted) showError(context, e);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// Chip showing the activity's type in a group; tap to change it.
class _TypeMenu extends ConsumerWidget {
  const _TypeMenu({required this.groupId, required this.currentTypeId, required this.currentName, required this.onChanged});

  final String groupId;
  final String currentTypeId;
  final String currentName;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final types = ref.watch(typesProvider(groupId)).value ?? const [];
    return PopupMenuButton<String>(
      tooltip: 'Change type',
      onSelected: (id) {
        if (id != currentTypeId) onChanged(id);
      },
      itemBuilder: (_) => [
        for (final t in types) CheckedPopupMenuItem(value: t.id, checked: t.id == currentTypeId, child: Text(t.name)),
      ],
      child: Chip(label: Text(currentName), avatar: const Icon(Icons.label_outline, size: 16)),
    );
  }
}

class _HistorySection extends ConsumerWidget {
  const _HistorySection({required this.activityId});

  final String activityId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = {for (final g in ref.watch(myGroupsProvider).value ?? const <Group>[]) g.id: g.name};
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text('History', style: Theme.of(context).textTheme.titleMedium),
        ),
        AsyncBody(
          value: ref.watch(activityHistoryProvider(activityId)),
          builder: (entries) => Column(
            children: [
              for (final e in entries)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.history, size: 20),
                  title: Text('@${e.actorUsername ?? 'someone'} ${describeChange(e, groups)}'),
                  subtitle: Text(DateFormat('d MMM y, h:mm a').format(e.createdAt.toLocal()), style: muted),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

const _fieldNames = {
  'name': 'name',
  'description': 'description',
  'location': 'location',
  'price_min': 'min price',
  'price_max': 'max price',
  'currency': 'currency',
  'url': 'link',
};

/// Plain-language summary of a change-log entry about an activity.
String describeChange(ChangeEntry e, Map<String, String> groupNames) {
  String group() {
    final id = (e.after ?? e.before)?['group_id'] as String?;
    return groupNames[id] ?? 'a group';
  }

  String show(Object? v) => v == null || '$v'.isEmpty ? 'empty' : '“$v”';

  switch ((e.entityType, e.action)) {
    case ('activity', 'created'):
      return 'created this activity';
    case ('activity', 'deleted'):
      return 'deleted this activity';
    case ('activity', 'updated'):
      final changes = [
        for (final k in (e.after ?? const {}).keys)
          if (_fieldNames.containsKey(k)) '${_fieldNames[k]} from ${show(e.before?[k])} to ${show(e.after?[k])}',
      ];
      return changes.isEmpty ? 'edited this activity' : 'changed ${changes.join(', ')}';
    case ('activity_photo', 'created'):
      return 'added a photo';
    case ('activity_photo', 'deleted'):
      return 'removed a photo';
    case ('group_activity', 'created'):
      return 'shared it into ${group()}';
    case ('group_activity', 'deleted'):
      return 'removed it from ${group()}';
    case ('group_activity', 'type_changed'):
      return 'changed its type in ${group()}';
    default:
      return '${e.action.replaceAll('_', ' ')} (${e.entityType.replaceAll('_', ' ')})';
  }
}
