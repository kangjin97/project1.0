import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/schedule_models.dart';

final _time = DateFormat('h:mm a');
final _dayHeader = DateFormat('EEEE, d MMMM');
final _shortDay = DateFormat('EEE d MMM');

String formatTime(DateTime t) => _time.format(t);
String formatShortDay(DateTime d) => _shortDay.format(d);

/// "Today", "Tomorrow", or e.g. "Saturday, 12 October".
String dayHeading(DateTime day) {
  final today = dateOnly(DateTime.now());
  if (isSameDay(day, today)) return 'Today · ${_dayHeader.format(day)}';
  if (isSameDay(day, addDays(today, 1))) return 'Tomorrow · ${_dayHeader.format(day)}';
  return _dayHeader.format(day);
}

/// When the entry happens, as seen on [day] (matters for multi-day entries).
String timeLabel(ScheduleEntry e, {DateTime? day}) {
  if (e.isUnscheduled) return 'No date yet';
  if (e.allDay) return 'All day';
  final start = e.startAt!, end = e.endAt!;
  if (isSameDay(start, end) || day == null) {
    final range = '${formatTime(start)} – ${formatTime(end)}';
    return isSameDay(start, end) ? range : '${formatShortDay(start)} ${formatTime(start)} – ${formatShortDay(end)} ${formatTime(end)}';
  }
  if (isSameDay(day, start)) return 'From ${formatTime(start)}';
  if (isSameDay(day, end)) return 'Until ${formatTime(end)}';
  return 'All day';
}

/// Full description of when, for detail views.
String whenLabel(ScheduleEntry e) {
  if (e.isUnscheduled) return 'No date yet';
  if (e.allDay) return '${DateFormat('EEEE, d MMMM y').format(e.date!)} · All day';
  final start = e.startAt!, end = e.endAt!;
  if (isSameDay(start, end)) {
    return '${DateFormat('EEEE, d MMMM y').format(start)} · ${formatTime(start)} – ${formatTime(end)}';
  }
  return '${formatShortDay(start)} ${formatTime(start)} – ${formatShortDay(end)} ${formatTime(end)}';
}

/// One entry in a list. Entries the user is in are highlighted.
class EntryTile extends StatelessWidget {
  const EntryTile({super.key, required this.entry, this.day, this.showGroup = true, this.onTap});

  final ScheduleEntry entry;
  final DateTime? day;
  final bool showGroup;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final e = entry;
    final accent = e.iAmIn ? scheme.primary : scheme.outlineVariant;
    final muted = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      color: e.iAmIn ? scheme.primaryContainer.withValues(alpha: 0.45) : null,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: accent),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(timeLabel(e, day: day), style: theme.textTheme.labelMedium),
                          const Spacer(),
                          if (e.iHaveClash)
                            Tooltip(
                              message: 'Overlaps with something else you have',
                              child: Icon(Icons.warning_amber_rounded, size: 18, color: scheme.error),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (e.isEvent) ...[
                            Icon(Icons.lightbulb_outline, size: 16, color: scheme.tertiary),
                            const SizedBox(width: 4),
                          ],
                          Expanded(
                            child: Text(e.displayTitle,
                                style: theme.textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (showGroup) e.groupName,
                          if (e.isEvent) 'Event',
                          '${e.participants.length} going',
                          if (!e.iAmIn) 'You’re not in this',
                        ].join(' · '),
                        style: muted,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Entries grouped under day headings, for every day in [days] that has any.
class AgendaList extends StatelessWidget {
  const AgendaList({
    super.key,
    required this.entries,
    required this.days,
    required this.onTap,
    this.showGroup = true,
    this.header = const [],
    this.footer = const [],
    this.emptyMessage = 'Nothing planned.',
  });

  final List<ScheduleEntry> entries;
  final List<DateTime> days;
  final ValueChanged<ScheduleEntry> onTap;
  final bool showGroup;
  final List<Widget> header;
  final List<Widget> footer;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final children = <Widget>[...header];
    var any = false;
    for (final day in days) {
      final onDay = entries.where((e) => e.occursOn(day)).toList();
      if (onDay.isEmpty) continue;
      any = true;
      children.add(Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(dayHeading(day), style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
      ));
      for (final e in onDay) {
        children.add(EntryTile(entry: e, day: day, showGroup: showGroup, onTap: () => onTap(e)));
      }
    }
    if (!any) {
      children.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: Column(
          children: [
            Icon(Icons.event_available_outlined, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(emptyMessage, textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
          ],
        ),
      ));
    }
    children.addAll(footer);
    return ListView(padding: const EdgeInsets.only(bottom: 96), children: children);
  }
}

/// Asks the planner whether to go ahead despite clashes. True = proceed.
Future<bool> confirmClashes(BuildContext context, List<ScheduleClash> clashes) async {
  final byUser = <String, List<ScheduleClash>>{};
  for (final c in clashes) {
    byUser.putIfAbsent(c.username, () => []).add(c);
  }
  String when(ScheduleClash c) {
    if (c.allDay && c.date != null) return '${formatShortDay(c.date!)}, all day';
    if (c.startAt != null && c.endAt != null) {
      return '${formatShortDay(c.startAt!)}, ${formatTime(c.startAt!)} – ${formatTime(c.endAt!)}';
    }
    return '';
  }

  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.event_busy_outlined),
      title: const Text('Schedule clash'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final MapEntry(key: user, value: items) in byUser.entries) ...[
              Text('@$user already has:', style: Theme.of(context).textTheme.titleSmall),
              for (final c in items)
                Padding(
                  padding: const EdgeInsets.only(left: 8, top: 2),
                  child: Text('• ${c.title} (${when(c)})'),
                ),
              const SizedBox(height: 8),
            ],
            const Text('Add them anyway? They’ll be told about the clash.'),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Proceed')),
      ],
    ),
  );
  return ok ?? false;
}
