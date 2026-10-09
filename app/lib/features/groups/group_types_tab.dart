import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/activities_repository.dart';
import '../../data/groups_repository.dart';
import '../../data/models.dart';
import '../../widgets/async_body.dart';
import '../../widgets/dialogs.dart';

/// The group's activity types, and the merges that fold labels into them.
class GroupTypesTab extends ConsumerWidget {
  const GroupTypesTab({super.key, required this.groupId});

  final String groupId;

  Future<void> _run(BuildContext context, WidgetRef ref, Future<void> Function() action) async {
    try {
      await action();
      ref.invalidate(typesProvider(groupId));
      ref.invalidate(mergesProvider(groupId));
      ref.invalidate(groupActivitiesProvider(groupId));
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(groupsRepositoryProvider);
    final theme = Theme.of(context);
    final merges = ref.watch(mergesProvider(groupId)).value ?? const <TypeMerge>[];
    final counts = <String, int>{};
    for (final ga in ref.watch(groupActivitiesProvider(groupId)).value ?? const <GroupActivity>[]) {
      counts[ga.typeId] = (counts[ga.typeId] ?? 0) + 1;
    }

    return AsyncBody(
      value: ref.watch(typesProvider(groupId)),
      builder: (types) => ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Types label the activities in this group. An activity shared with its owner’s label lands in the '
              'type with the same name, or in the type that label was merged into.',
              style: theme.textTheme.bodyMedium,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    final name = await promptText(context, title: 'New type', label: 'Name', action: 'Add');
                    if (name == null || name.trim().isEmpty || !context.mounted) return;
                    await _run(context, ref, () => repo.addType(groupId, name));
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Add type'),
                ),
                FilledButton.tonalIcon(
                  onPressed: types.length < 2
                      ? null
                      : () => showModalBottomSheet(
                            context: context,
                            useRootNavigator: true,
                            isScrollControlled: true,
                            showDragHandle: true,
                            builder: (_) => _MergeSheet(groupId: groupId, types: types),
                          ),
                  icon: const Icon(Icons.merge_type),
                  label: const Text('Merge types'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          for (final t in types)
            _TypeTile(
              type: t,
              count: counts[t.id] ?? 0,
              mergedIn: [for (final m in merges) if (m.targetTypeId == t.id) m],
              onRename: () async {
                final name = await promptText(context, title: 'Rename type', label: 'Name', action: 'Save', initial: t.name);
                if (name == null || name.trim().isEmpty || !context.mounted) return;
                await _run(context, ref, () => repo.renameType(t.id, name));
              },
              onDelete: () => _run(context, ref, () => repo.deleteType(t.id)),
              onUnmerge: (m) async {
                final ok = await confirm(context,
                    title: 'Stop merging “${m.sourceName}”?',
                    message: 'Activities that came in labelled “${m.sourceName}” move back to a type of that name.',
                    action: 'Unmerge');
                if (ok && context.mounted) await _run(context, ref, () => repo.removeMerge(m.id));
              },
            ),
        ],
      ),
    );
  }
}

class _TypeTile extends StatelessWidget {
  const _TypeTile({
    required this.type,
    required this.count,
    required this.mergedIn,
    required this.onRename,
    required this.onDelete,
    required this.onUnmerge,
  });

  final ActivityType type;
  final int count;
  final List<TypeMerge> mergedIn;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final ValueChanged<TypeMerge> onUnmerge;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall;
    return ListTile(
      leading: Icon(mergedIn.isEmpty ? Icons.label_outline : Icons.merge_type),
      title: Text(type.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$count activit${count == 1 ? 'y' : 'ies'}', style: muted),
          if (mergedIn.isNotEmpty) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Includes', style: muted),
                for (final m in mergedIn)
                  InputChip(
                    label: Text(m.sourceName),
                    visualDensity: VisualDensity.compact,
                    deleteButtonTooltipMessage: 'Unmerge',
                    onDeleted: () => onUnmerge(m),
                  ),
              ],
            ),
          ],
        ],
      ),
      isThreeLine: mergedIn.isNotEmpty,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(tooltip: 'Rename', icon: const Icon(Icons.edit_outlined), onPressed: onRename),
          IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline), onPressed: onDelete),
        ],
      ),
    );
  }
}

/// Pick types to merge and the type they become.
class _MergeSheet extends ConsumerStatefulWidget {
  const _MergeSheet({required this.groupId, required this.types});

  final String groupId;
  final List<ActivityType> types;

  @override
  ConsumerState<_MergeSheet> createState() => _MergeSheetState();
}

class _MergeSheetState extends ConsumerState<_MergeSheet> {
  static const _newType = '__new__';

  final Set<String> _sources = {};
  String? _target;
  final _newName = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _newName.dispose();
    super.dispose();
  }

  bool get _ready {
    if (_target == null) return false;
    if (_target == _newType) return _newName.text.trim().isNotEmpty && _sources.isNotEmpty;
    return _sources.any((s) => s != _target);
  }

  Future<void> _merge() async {
    setState(() => _busy = true);
    try {
      await ref.read(groupsRepositoryProvider).mergeTypes(
            widget.groupId,
            _sources.toList(),
            targetTypeId: _target == _newType ? null : _target,
            targetName: _target == _newType ? _newName.text : null,
          );
      ref.invalidate(typesProvider(widget.groupId));
      ref.invalidate(mergesProvider(widget.groupId));
      ref.invalidate(groupActivitiesProvider(widget.groupId));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Merge types', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Their activities move into one type, and anything shared later with one of these labels goes there too.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          Text('Merge these', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in widget.types)
                FilterChip(
                  label: Text(t.name),
                  selected: _sources.contains(t.id),
                  onSelected: t.id == _target
                      ? null
                      : (on) => setState(() => on ? _sources.add(t.id) : _sources.remove(t.id)),
                ),
            ],
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _target,
            decoration: const InputDecoration(labelText: 'Into', border: OutlineInputBorder()),
            items: [
              for (final t in widget.types) DropdownMenuItem(value: t.id, child: Text(t.name)),
              const DropdownMenuItem(value: _newType, child: Text('A new type…')),
            ],
            onChanged: (v) => setState(() {
              _target = v;
              _sources.remove(v);
            }),
          ),
          if (_target == _newType) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _newName,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'New type name', border: OutlineInputBorder()),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy || !_ready ? null : _merge,
            child: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Merge')),
          ),
        ],
      ),
    );
  }
}
