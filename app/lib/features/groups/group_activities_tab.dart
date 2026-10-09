import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/activities_repository.dart';
import '../../data/groups_repository.dart';
import '../../data/models.dart';
import '../../widgets/async_body.dart';
import '../../widgets/dialogs.dart';
import '../activities/activity_widgets.dart';
import '../activities/share_activity_sheet.dart';

enum _Sort { newest, name, priceLow }

/// A group's shared activities, with search, filters and sorting.
class GroupActivitiesTab extends ConsumerStatefulWidget {
  const GroupActivitiesTab({super.key, required this.groupId});

  final String groupId;

  @override
  ConsumerState<GroupActivitiesTab> createState() => _GroupActivitiesTabState();
}

class _GroupActivitiesTabState extends ConsumerState<GroupActivitiesTab> {
  String _query = '';
  final Set<String> _types = {};
  double? _maxBudget;
  String? _addedBy;
  _Sort _sort = _Sort.newest;

  bool get _filtering => _types.isNotEmpty || _maxBudget != null || _addedBy != null;

  List<GroupActivity> _apply(List<GroupActivity> all) {
    final q = _query.trim().toLowerCase();
    final list = all.where((ga) {
      final a = ga.activity;
      if (q.isNotEmpty &&
          ![a.name, a.description, a.location, ga.typeName].any((f) => f?.toLowerCase().contains(q) ?? false)) {
        return false;
      }
      if (_types.isNotEmpty && !_types.contains(ga.typeId)) return false;
      if (_addedBy != null && ga.sharedById != _addedBy) return false;
      if (_maxBudget != null && !a.fitsBudget(max: _maxBudget)) return false;
      return true;
    }).toList();

    double price(GroupActivity ga) => ga.activity.priceMin ?? ga.activity.priceMax ?? double.infinity;
    switch (_sort) {
      case _Sort.newest:
        list.sort((x, y) => y.sharedAt.compareTo(x.sharedAt));
      case _Sort.name:
        list.sort((x, y) => x.activity.name.toLowerCase().compareTo(y.activity.name.toLowerCase()));
      case _Sort.priceLow:
        list.sort((x, y) => price(x).compareTo(price(y)));
    }
    return list;
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

  @override
  Widget build(BuildContext context) {
    final groupId = widget.groupId;
    final types = ref.watch(typesProvider(groupId)).value ?? const [];
    final members = ref.watch(membersProvider(groupId)).value ?? const [];

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(groupActivitiesProvider(groupId));
        await ref.read(groupActivitiesProvider(groupId).future);
      },
      child: AsyncBody(
        value: ref.watch(groupActivitiesProvider(groupId)),
        builder: (all) {
          final list = _apply(all);
          return ListView(
            padding: const EdgeInsets.only(bottom: 48),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: SearchBar(
                        hintText: 'Search activities',
                        leading: const Icon(Icons.search),
                        elevation: const WidgetStatePropertyAll(0),
                        onChanged: (v) => setState(() => _query = v),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: () => showShareActivitySheet(context, groupId: groupId),
                      icon: const Icon(Icons.add),
                      label: const Text('Add'),
                    ),
                  ],
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
                    FilterChip(
                      label: Text(_maxBudget == null ? 'Budget' : 'Up to ${_maxBudget!.toStringAsFixed(0)}'),
                      selected: _maxBudget != null,
                      onSelected: (_) => _setBudget(),
                    ),
                    const SizedBox(width: 8),
                    PopupMenuButton<String?>(
                      tooltip: 'Added by',
                      onSelected: (id) => setState(() => _addedBy = id),
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: null, child: Text('Anyone')),
                        for (final m in members) PopupMenuItem(value: m.profile.id, child: Text(m.profile.label)),
                      ],
                      child: Chip(
                        avatar: const Icon(Icons.person_outline, size: 18),
                        label: Text(_addedBy == null
                            ? 'Added by'
                            : members.where((m) => m.profile.id == _addedBy).firstOrNull?.profile.label ?? 'Added by'),
                      ),
                    ),
                    for (final t in types) ...[
                      const SizedBox(width: 8),
                      FilterChip(
                        label: Text(t.name),
                        selected: _types.contains(t.id),
                        onSelected: (on) => setState(() => on ? _types.add(t.id) : _types.remove(t.id)),
                      ),
                    ],
                    if (_filtering) ...[
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () => setState(() {
                          _types.clear();
                          _maxBudget = null;
                          _addedBy = null;
                        }),
                        child: const Text('Clear'),
                      ),
                    ],
                  ],
                ),
              ),
              if (all.isEmpty)
                const EmptyState(
                  icon: Icons.local_activity_outlined,
                  message: 'No activities in this group yet.\nTap Add to share one of yours or create a new one.',
                )
              else if (list.isEmpty)
                const EmptyState(icon: Icons.filter_alt_off_outlined, message: 'Nothing matches these filters.')
              else
                for (final ga in list)
                  ActivityCard(
                    activity: ga.activity,
                    typeName: ga.typeName,
                    footer: ga.sharedByUsername == null ? null : 'by @${ga.sharedByUsername}',
                    onTap: () => context.push('/activities/${ga.activityId}'),
                  ),
            ],
          );
        },
      ),
    );
  }
}
