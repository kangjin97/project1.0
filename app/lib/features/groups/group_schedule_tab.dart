import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/app_clock.dart';
import '../../data/schedule_models.dart';
import '../../data/schedule_repository.dart';
import '../../widgets/async_body.dart';
import '../schedule/entry_detail_sheet.dart';
import '../schedule/entry_editor.dart';
import '../schedule/schedule_widgets.dart';

/// The whole group's plans: ideas with no date yet, then upcoming days.
/// Plans the user is in are highlighted.
class GroupScheduleTab extends ConsumerStatefulWidget {
  const GroupScheduleTab({super.key, required this.groupId});

  final String groupId;

  @override
  ConsumerState<GroupScheduleTab> createState() => _GroupScheduleTabState();
}

class _GroupScheduleTabState extends ConsumerState<GroupScheduleTab> {
  int _weeks = 8;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = AppClock.today();
    final ScheduleQuery query =
        (from: today, to: addDays(today, _weeks * 7 - 1), groupId: widget.groupId, includeUnscheduled: true);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(scheduleProvider(query));
        await ref.read(scheduleProvider(query).future);
      },
      child: AsyncBody(
        value: ref.watch(scheduleProvider(query)),
        builder: (entries) {
          final ideas = entries.where((e) => e.isUnscheduled).toList();
          void open(ScheduleEntry e) => showEntryDetail(context, query, e.id);
          return AgendaList(
            entries: entries.where((e) => !e.isUnscheduled).toList(),
            days: [for (var i = 0; i < _weeks * 7; i++) addDays(today, i)],
            showGroup: false,
            onTap: open,
            emptyMessage: 'Nothing planned in the next $_weeks weeks.',
            header: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('Your plans are highlighted.',
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    ),
                    FilledButton.icon(
                      onPressed: () => showEntryEditor(context, groupId: widget.groupId),
                      icon: const Icon(Icons.add),
                      label: const Text('Add to schedule'),
                    ),
                  ],
                ),
              ),
              if (ideas.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Row(
                    children: [
                      Icon(Icons.lightbulb_outline, size: 18, color: theme.colorScheme.tertiary),
                      const SizedBox(width: 6),
                      Text('Ideas · not scheduled yet',
                          style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.tertiary)),
                    ],
                  ),
                ),
                for (final e in ideas) EntryTile(entry: e, showGroup: false, onTap: () => open(e)),
              ],
            ],
            footer: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: OutlinedButton(
                    onPressed: () => setState(() => _weeks += 8),
                    child: const Text('Show 8 more weeks'),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
