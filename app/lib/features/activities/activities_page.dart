import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/activities_repository.dart';
import '../../data/models.dart';
import '../../widgets/async_body.dart';
import '../../widgets/dialogs.dart';
import 'activity_form_page.dart';
import 'activity_widgets.dart';

enum _Sort { newest, name, priceLow }

enum _Sharing { all, private, shared }

/// The activities you created, with search, label and budget filters.
class ActivitiesPage extends ConsumerStatefulWidget {
  const ActivitiesPage({super.key});

  @override
  ConsumerState<ActivitiesPage> createState() => _ActivitiesPageState();
}

class _ActivitiesPageState extends ConsumerState<ActivitiesPage> {
  String _query = '';
  final Set<String> _labels = {};
  _Sharing _sharing = _Sharing.all;
  double? _maxBudget;
  _Sort _sort = _Sort.newest;

  bool get _filtering => _labels.isNotEmpty || _sharing != _Sharing.all || _maxBudget != null;

  Future<void> _create() async {
    final id = await showActivityForm(context);
    if (id != null && mounted) context.push('/activities/$id');
  }

  Future<void> _setBudget() async {
    final v = await promptText(context,
        title: 'Maximum budget',
        label: 'Amount (leave empty for any)',
        action: 'Apply',
        initial: _maxBudget?.toStringAsFixed(0) ?? '');
    if (v == null) return;
    setState(() => _maxBudget = double.tryParse(v.trim()));
  }

  List<Activity> _apply(List<Activity> all) {
    final q = _query.trim().toLowerCase();
    final list = all.where((a) {
      if (q.isNotEmpty &&
          ![a.name, a.description, a.location, a.personalTypeName].any((f) => f?.toLowerCase().contains(q) ?? false)) {
        return false;
      }
      if (_labels.isNotEmpty && !_labels.contains(a.personalTypeId)) return false;
      final shared = (a.sharedGroupCount ?? 0) > 0;
      if (_sharing == _Sharing.private && shared) return false;
      if (_sharing == _Sharing.shared && !shared) return false;
      if (_maxBudget != null && !a.fitsBudget(max: _maxBudget)) return false;
      return true;
    }).toList();

    double price(Activity a) => a.priceMin ?? a.priceMax ?? double.infinity;
    switch (_sort) {
      case _Sort.newest:
        list.sort((x, y) => y.createdAt.compareTo(x.createdAt));
      case _Sort.name:
        list.sort((x, y) => x.name.toLowerCase().compareTo(y.name.toLowerCase()));
      case _Sort.priceLow:
        list.sort((x, y) => price(x).compareTo(price(y)));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 720;
    final labels = ref.watch(labelsProvider).value ?? const <PersonalType>[];
    return Scaffold(
      appBar: AppBar(
        title: const Text('My activities'),
        actions: [
          TextButton.icon(
            onPressed: () => showModalBottomSheet(
              context: context,
              useRootNavigator: true,
              isScrollControlled: true,
              showDragHandle: true,
              builder: (_) => const _LabelsSheet(),
            ),
            icon: const Icon(Icons.label_outline),
            label: const Text('Labels'),
          ),
          if (narrow)
            IconButton(
              tooltip: 'Sign out',
              icon: const Icon(Icons.logout),
              onPressed: () => Supabase.instance.client.auth.signOut(),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('New activity'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(labelsProvider);
          ref.invalidate(myActivitiesProvider);
          await ref.read(myActivitiesProvider.future);
        },
        child: AsyncBody(
          value: ref.watch(myActivitiesProvider),
          builder: (all) {
            if (all.isEmpty) {
              return ListView(
                children: const [
                  EmptyState(
                    icon: Icons.local_activity_outlined,
                    message: 'No activities yet.\nAdd ideas for things to do, then share them with your groups.',
                  ),
                ],
              );
            }
            final list = _apply(all);
            return ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: SearchBar(
                    hintText: 'Search name, description, location or label',
                    leading: const Icon(Icons.search),
                    elevation: const WidgetStatePropertyAll(0),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    children: [
                      PopupMenuButton<_Sort>(
                        tooltip: 'Sort',
                        initialValue: _sort,
                        onSelected: (s) => setState(() => _sort = s),
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: _Sort.newest, child: Text('Newest first')),
                          PopupMenuItem(value: _Sort.name, child: Text('Name')),
                          PopupMenuItem(value: _Sort.priceLow, child: Text('Price: low to high')),
                        ],
                        child: Chip(
                          avatar: const Icon(Icons.sort, size: 18),
                          label: Text(switch (_sort) {
                            _Sort.newest => 'Newest',
                            _Sort.name => 'Name',
                            _Sort.priceLow => 'Cheapest',
                          }),
                        ),
                      ),
                      const SizedBox(width: 8),
                      PopupMenuButton<_Sharing>(
                        tooltip: 'Sharing',
                        initialValue: _sharing,
                        onSelected: (s) => setState(() => _sharing = s),
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: _Sharing.all, child: Text('All')),
                          PopupMenuItem(value: _Sharing.private, child: Text('Private only')),
                          PopupMenuItem(value: _Sharing.shared, child: Text('Shared to a group')),
                        ],
                        child: Chip(
                          avatar: const Icon(Icons.group_outlined, size: 18),
                          backgroundColor:
                              _sharing == _Sharing.all ? null : Theme.of(context).colorScheme.secondaryContainer,
                          label: Text(switch (_sharing) {
                            _Sharing.all => 'Sharing',
                            _Sharing.private => 'Private',
                            _Sharing.shared => 'Shared',
                          }),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        label: Text(_maxBudget == null ? 'Budget' : 'Up to ${_maxBudget!.toStringAsFixed(0)}'),
                        selected: _maxBudget != null,
                        onSelected: (_) => _setBudget(),
                      ),
                      for (final l in labels) ...[
                        const SizedBox(width: 8),
                        FilterChip(
                          avatar: const Icon(Icons.label_outline, size: 16),
                          label: Text(l.name),
                          selected: _labels.contains(l.id),
                          onSelected: (on) => setState(() => on ? _labels.add(l.id) : _labels.remove(l.id)),
                        ),
                      ],
                      if (_filtering) ...[
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () => setState(() {
                            _labels.clear();
                            _sharing = _Sharing.all;
                            _maxBudget = null;
                          }),
                          child: const Text('Clear'),
                        ),
                      ],
                    ],
                  ),
                ),
                if (list.isEmpty) const EmptyState(icon: Icons.search_off, message: 'Nothing matches.'),
                for (final a in list)
                  ActivityCard(
                    activity: a,
                    typeName: a.personalTypeName,
                    footer: switch (a.sharedGroupCount ?? 0) {
                      0 => 'Private',
                      1 => 'In 1 group',
                      final n => 'In $n groups',
                    },
                    onTap: () => context.push('/activities/${a.id}'),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Add, rename and delete your labels.
class _LabelsSheet extends ConsumerWidget {
  const _LabelsSheet();

  Future<void> _run(BuildContext context, WidgetRef ref, Future<void> Function() action) async {
    try {
      await action();
      invalidateLabels(ref);
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(activitiesRepositoryProvider);
    return SizedBox(
      height: 440,
      child: AsyncBody(
        value: ref.watch(labelsProvider),
        builder: (labels) => ListView(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Your labels', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(
                    'Only you see these. Renaming one re-files its activities in every group.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            for (final l in labels)
              ListTile(
                leading: const Icon(Icons.label_outline),
                title: Text(l.name),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Rename',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () async {
                        final name =
                            await promptText(context, title: 'Rename label', label: 'Label', action: 'Save', initial: l.name);
                        if (name == null || name.trim().isEmpty || !context.mounted) return;
                        await _run(context, ref, () => repo.renameLabel(l.id, name));
                      },
                    ),
                    IconButton(
                      tooltip: 'Delete',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        final ok = await confirm(context,
                            title: 'Delete “${l.name}”?',
                            message: 'Activities lose this label but keep their types in groups.',
                            action: 'Delete');
                        if (ok && context.mounted) await _run(context, ref, () => repo.deleteLabel(l.id));
                      },
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final name = await promptText(context, title: 'New label', label: 'Label', action: 'Add');
                    if (name == null || name.trim().isEmpty || !context.mounted) return;
                    await _run(context, ref, () => repo.addLabel(name));
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('New label'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
