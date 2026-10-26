import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/activities_repository.dart';
import '../../data/activity_sheet.dart';
import '../../data/app_clock.dart';
import '../../data/export/save_file.dart';
import '../../data/geo.dart';
import '../../data/models.dart';
import '../../data/places_repository.dart';
import '../../widgets/async_body.dart';
import '../../widgets/dialogs.dart';
import 'activity_form_page.dart';
import 'activity_widgets.dart';
import 'import_activities_page.dart';
import 'near_filter.dart';

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
  bool _withLink = false;
  bool _withPhotos = false;
  NearFilter? _near;

  /// Picking activities to export (#111).
  bool _selecting = false;
  final Set<String> _selected = {};
  List<Activity> _shown = const [];
  _Sort _sort = _Sort.newest;

  bool get _filtering =>
      _labels.isNotEmpty || _sharing != _Sharing.all || _maxBudget != null || _withLink || _withPhotos || _near != null;

  Future<void> _import() async {
    final count = await showActivityImport(context);
    if (count != null && mounted) showMessage(context, 'Imported $count ${count == 1 ? 'activity' : 'activities'}.');
  }

  /// The selected activities in the import layout, so someone else can import them.
  Future<void> _exportSelected(List<Activity> all) async {
    final chosen = [
      for (final a in all)
        if (_selected.contains(a.id)) a,
    ];
    if (chosen.isEmpty) return;
    try {
      final now = AppClock.today();
      final date = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      await saveFile(
        Uint8List.fromList(activitiesToExcel(chosen)),
        name: 'EasyPlan activities $date.xlsx',
        mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      if (!mounted) return;
      setState(() {
        _selecting = false;
        _selected.clear();
      });
      showMessage(context, 'Exported ${chosen.length} ${chosen.length == 1 ? 'activity' : 'activities'}.');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _create() async {
    final id = await showActivityForm(context);
    if (id != null && mounted) context.push('/activities/$id');
  }

  Future<void> _setBudget() async {
    final v = await promptText(
      context,
      title: 'Maximum budget',
      label: 'Amount (leave empty for any)',
      action: 'Apply',
      initial: _maxBudget?.toStringAsFixed(0) ?? '',
    );
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
      if (_withLink && !a.hasLink) return false;
      if (_withPhotos && !a.hasPhotos) return false;
      return true;
    }).toList();

    double price(Activity a) => a.priceMin ?? a.priceMax ?? double.infinity;
    switch (_sort) {
      case _Sort.newest:
        list.sort(Activity.newestFirst);
      case _Sort.name:
        list.sort((x, y) => x.name.toLowerCase().compareTo(y.name.toLowerCase()));
      case _Sort.priceLow:
        list.sort((x, y) => price(x).compareTo(price(y)));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final labels = ref.watch(labelsProvider).value ?? const <PersonalType>[];
    // Distances for the "Near…" filter: the places of all your activities, looked up once.
    final coordinates = _near == null
        ? null
        : ref.watch(
            placeCoordinatesProvider(
              placeKey((ref.watch(myActivitiesProvider).value ?? const <Activity>[]).map((a) => a.placeId)),
            ),
          );
    return Scaffold(
      appBar: _selecting
          ? AppBar(
              leading: IconButton(
                tooltip: 'Cancel',
                icon: const Icon(Icons.close),
                onPressed: () => setState(() {
                  _selecting = false;
                  _selected.clear();
                }),
              ),
              title: Text('${_selected.length} selected'),
              actions: [
                TextButton(
                  onPressed: () => setState(() => _selected.addAll(_shown.map((a) => a.id))),
                  child: const Text('Select all'),
                ),
                FilledButton.icon(
                  onPressed: _selected.isEmpty
                      ? null
                      : () => _exportSelected(ref.read(myActivitiesProvider).value ?? const []),
                  icon: const Icon(Icons.download),
                  label: const Text('Export'),
                ),
                const SizedBox(width: 8),
              ],
            )
          : AppBar(
              title: const Text('My activities'),
              actions: [
                PopupMenuButton<String>(
                  tooltip: 'Import or export',
                  icon: const Icon(Icons.import_export),
                  onSelected: (v) => switch (v) {
                    'import' => _import(),
                    'export' => setState(() => _selecting = true),
                    _ => downloadActivityTemplate(),
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'import',
                      child: ListTile(
                        leading: Icon(Icons.upload_file),
                        title: Text('Import from a spreadsheet'),
                        subtitle: Text('Many activities at once from Excel or CSV'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'export',
                      child: ListTile(
                        leading: Icon(Icons.checklist),
                        title: Text('Select to export'),
                        subtitle: Text('Tick activities to save as a sheet others can import'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'template',
                      child: ListTile(
                        leading: Icon(Icons.download),
                        title: Text('Download template'),
                        subtitle: Text('A blank sheet to fill in'),
                      ),
                    ),
                  ],
                ),
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
              ],
            ),
      floatingActionButton: _selecting
          ? null
          : FloatingActionButton.extended(
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
            var list = _apply(all);
            final distances = <String, double>{};
            var unmeasured = const <Activity>[];
            if (_near != null) {
              final near = applyNear(list, _near!, coordinates?.value?.byPlace ?? const {}, (a) => a.placeId);
              list = [for (final (a, _) in near.within) a];
              distances.addAll({for (final (a, km) in near.within) a.id: km});
              unmeasured = near.unmeasured;
            }
            _shown = list;
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
                          backgroundColor: _sharing == _Sharing.all
                              ? null
                              : Theme.of(context).colorScheme.secondaryContainer,
                          label: Text(switch (_sharing) {
                            _Sharing.all => 'Sharing',
                            _Sharing.private => 'Private',
                            _Sharing.shared => 'Shared',
                          }),
                        ),
                      ),
                      const SizedBox(width: 8),
                      NearFilterChip(value: _near, onChanged: (v) => setState(() => _near = v)),
                      const SizedBox(width: 8),
                      FilterChip(
                        label: Text(_maxBudget == null ? 'Budget' : 'Up to ${_maxBudget!.toStringAsFixed(0)}'),
                        selected: _maxBudget != null,
                        onSelected: (_) => _setBudget(),
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        avatar: const Icon(Icons.link, size: 16),
                        label: const Text('Has link'),
                        selected: _withLink,
                        onSelected: (on) => setState(() => _withLink = on),
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        avatar: const Icon(Icons.photo_outlined, size: 16),
                        label: const Text('Has photos'),
                        selected: _withPhotos,
                        onSelected: (on) => setState(() => _withPhotos = on),
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
                            _withLink = false;
                            _withPhotos = false;
                            _near = null;
                          }),
                          child: const Text('Clear'),
                        ),
                      ],
                    ],
                  ),
                ),
                if (coordinates != null) NearNote(coordinates: coordinates, unmeasured: unmeasured),
                if (list.isEmpty && !(coordinates?.isLoading ?? false))
                  EmptyState(
                    icon: Icons.search_off,
                    message: _near == null
                        ? 'Nothing matches.'
                        : 'Nothing within ${formatDistance(_near!.km)} of ${_near!.label}.',
                  ),
                for (final a in list)
                  ActivityCard(
                    activity: a,
                    trailing: _selecting
                        ? Checkbox(
                            value: _selected.contains(a.id),
                            onChanged: (on) =>
                                setState(() => on == true ? _selected.add(a.id) : _selected.remove(a.id)),
                          )
                        : null,
                    typeName: a.personalTypeName,
                    distanceKm: distances[a.id],
                    footer: switch (a.sharedGroupCount ?? 0) {
                      0 => 'Private',
                      1 => 'In 1 group',
                      final n => 'In $n groups',
                    },
                    onTap: _selecting
                        ? () => setState(() => _selected.contains(a.id) ? _selected.remove(a.id) : _selected.add(a.id))
                        : () => context.push('/activities/${a.id}'),
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
                        final name = await promptText(
                          context,
                          title: 'Rename label',
                          label: 'Label',
                          action: 'Save',
                          initial: l.name,
                        );
                        if (name == null || name.trim().isEmpty || !context.mounted) return;
                        await _run(context, ref, () => repo.renameLabel(l.id, name));
                      },
                    ),
                    IconButton(
                      tooltip: 'Delete',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        final ok = await confirm(
                          context,
                          title: 'Delete “${l.name}”?',
                          message: 'Activities lose this label but keep their types in groups.',
                          action: 'Delete',
                        );
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
