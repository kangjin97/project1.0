import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/activities_repository.dart';
import '../../data/groups_repository.dart';
import '../../widgets/dialogs.dart';
import 'activity_form_page.dart';

/// Shares an activity into a group with a type.
///
/// Pass [activityId] to pick the group, or [groupId] to pick (or create) the
/// activity. Returns true when shared.
Future<bool> showShareActivitySheet(BuildContext context, {String? activityId, String? groupId}) async {
  assert(activityId != null || groupId != null);
  final shared = await showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ShareSheet(activityId: activityId, groupId: groupId),
  );
  return shared ?? false;
}

class _ShareSheet extends ConsumerStatefulWidget {
  const _ShareSheet({this.activityId, this.groupId});

  final String? activityId;
  final String? groupId;

  @override
  ConsumerState<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends ConsumerState<_ShareSheet> {
  late String? _activityId = widget.activityId;
  late String? _groupId = widget.groupId;
  String? _typeId;
  bool _pickByHand = false;
  bool _busy = false;

  /// The chosen activity's own label, if it has one.
  String? get _label {
    final id = _activityId;
    if (id == null) return null;
    final mine = ref.watch(myActivitiesProvider).value ?? const [];
    final fromList = mine.where((a) => a.id == id).firstOrNull;
    return (fromList ?? ref.watch(activityProvider(id)).value)?.personalTypeName;
  }

  bool get _byLabel => _label != null && !_pickByHand;

  Future<void> _newActivity() async {
    final id = await showActivityForm(context);
    if (id != null && mounted) {
      setState(() {
        _activityId = id;
        _pickByHand = false;
      });
    }
  }

  Future<void> _newType() async {
    final groupId = _groupId;
    if (groupId == null) return;
    final name = await promptText(context, title: 'New type', label: 'Name', action: 'Add');
    if (name == null || name.trim().isEmpty || !mounted) return;
    try {
      await ref.read(groupsRepositoryProvider).addType(groupId, name);
      final types = await ref.refresh(typesProvider(groupId).future);
      final added = types.where((t) => t.name.toLowerCase() == name.trim().toLowerCase());
      if (mounted && added.isNotEmpty) setState(() => _typeId = added.first.id);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _share() async {
    final (a, g, t) = (_activityId, _groupId, _byLabel ? null : _typeId);
    if (a == null || g == null || (t == null && !_byLabel)) return;
    setState(() => _busy = true);
    try {
      await ref.read(activitiesRepositoryProvider).share(activityId: a, groupId: g, typeId: t);
      invalidateActivity(ref, a, groupId: g);
      ref.invalidate(typesProvider(g));
      if (mounted) Navigator.pop(context, true);
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
          Text(widget.groupId != null ? 'Add an activity to this group' : 'Share to a group',
              style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          if (widget.activityId == null) _activityPicker() else _groupPicker(),
          const SizedBox(height: 16),
          if (_groupId != null && _activityId != null) _byLabel ? _labelPreview() : _typePicker(),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy || _activityId == null || _groupId == null || (_typeId == null && !_byLabel)
                ? null
                : _share,
            child: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Share')),
          ),
        ],
      ),
    );
  }

  Widget _groupPicker() {
    final groups = ref.watch(myGroupsProvider).value ?? const [];
    final already = {for (final s in ref.watch(sharedInProvider(widget.activityId!)).value ?? const []) s.groupId};
    final available = groups.where((g) => !already.contains(g.id)).toList();
    if (groups.isEmpty) return const Text('You’re not in any groups yet. Create or join one first.');
    if (available.isEmpty) return const Text('It’s already shared into all your groups.');
    return DropdownButtonFormField<String>(
      initialValue: _groupId,
      decoration: const InputDecoration(labelText: 'Group', border: OutlineInputBorder()),
      items: [for (final g in available) DropdownMenuItem(value: g.id, child: Text(g.name))],
      onChanged: (v) => setState(() {
        _groupId = v;
        _typeId = null;
      }),
    );
  }

  Widget _activityPicker() {
    final mine = ref.watch(myActivitiesProvider).value ?? const [];
    final inGroup = {for (final ga in ref.watch(groupActivitiesProvider(widget.groupId!)).value ?? const []) ga.activityId};
    final available = mine.where((a) => !inGroup.contains(a.id)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (available.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('All your activities are already in this group.'),
          )
        else
          DropdownButtonFormField<String>(
            key: ValueKey(_activityId),
            initialValue: available.any((a) => a.id == _activityId) ? _activityId : null,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'One of your activities', border: OutlineInputBorder()),
            items: [
              for (final a in available)
                DropdownMenuItem(value: a.id, child: Text(a.name, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() {
              _activityId = v;
              _pickByHand = false;
            }),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _newActivity,
            icon: const Icon(Icons.add),
            label: const Text('Create a new activity'),
          ),
        ),
      ],
    );
  }

  Widget _labelPreview() {
    final label = _label!;
    final preview = ref.watch(typePreviewProvider((_groupId!, label))).value;
    final theme = Theme.of(context);
    final text = preview == null
        ? 'Checking…'
        : preview.merged
            ? 'Filed under “${preview.typeName}”: this group merged “$label” into it.'
            : preview.isNew
                ? 'Adds a new type “${preview.typeName}” to this group.'
                : 'Filed under “${preview.typeName}”.';
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.label_outline, size: 18),
                const SizedBox(width: 8),
                Text('Your label: $label', style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 4),
            Text(text),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => setState(() => _pickByHand = true),
                child: const Text('Pick a type instead'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _typePicker() {
    final types = ref.watch(typesProvider(_groupId!)).value ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Type in this group', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in types)
              ChoiceChip(
                label: Text(t.name),
                selected: _typeId == t.id,
                onSelected: (_) => setState(() => _typeId = t.id),
              ),
            ActionChip(avatar: const Icon(Icons.add, size: 18), label: const Text('New type'), onPressed: _newType),
          ],
        ),
      ],
    );
  }
}
