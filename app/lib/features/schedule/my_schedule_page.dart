import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/app_clock.dart';
import '../../data/schedule_models.dart';
import '../../data/schedule_repository.dart';
import '../../widgets/async_body.dart';
import 'calendar_views.dart';
import 'entry_detail_sheet.dart';
import 'entry_editor.dart';
import 'schedule_widgets.dart';

enum _Mode { list, week, month }

/// Everything the user takes part in, across all groups, as a day-by-day list
/// or a week/month calendar. Phones open on the list, wide screens on the week.
class MySchedulePage extends ConsumerStatefulWidget {
  const MySchedulePage({super.key});

  @override
  ConsumerState<MySchedulePage> createState() => _MySchedulePageState();
}

class _MySchedulePageState extends ConsumerState<MySchedulePage> {
  _Mode? _chosen;
  DateTime _anchor = AppClock.today();
  int _listWeeks = 4;

  _Mode _mode(bool wide) => _chosen ?? (wide ? _Mode.week : _Mode.list);

  ScheduleQuery _query(_Mode mode) {
    switch (mode) {
      case _Mode.list:
        final today = AppClock.today();
        return (from: today, to: addDays(today, _listWeeks * 7 - 1), groupId: null, includeUnscheduled: false);
      case _Mode.week:
        final start = startOfWeek(_anchor);
        return (from: start, to: addDays(start, 6), groupId: null, includeUnscheduled: false);
      case _Mode.month:
        final start = MonthView.gridStart(_anchor);
        return (from: start, to: addDays(start, 41), groupId: null, includeUnscheduled: false);
    }
  }

  void _shift(_Mode mode, int direction) => setState(() {
    _anchor = mode == _Mode.week
        ? addDays(_anchor, 7 * direction)
        : DateTime(_anchor.year, _anchor.month + direction, 1);
  });

  String _periodLabel(_Mode mode) {
    if (mode == _Mode.month) return DateFormat('MMMM y').format(_anchor);
    final start = startOfWeek(_anchor), end = addDays(start, 6);
    return start.month == end.month
        ? '${start.day} – ${DateFormat('d MMM y').format(end)}'
        : '${DateFormat('d MMM').format(start)} – ${DateFormat('d MMM y').format(end)}';
  }

  Future<void> _add([DateTime? day]) async {
    await showEntryEditor(context, day: day);
  }

  void _openDay(ScheduleQuery query, List<ScheduleEntry> entries, DateTime day) {
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        final onDay = entries.where((e) => e.occursOn(day)).toList();
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 16),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
                  child: Row(
                    children: [
                      Expanded(child: Text(dayHeading(day), style: Theme.of(context).textTheme.titleMedium)),
                      TextButton.icon(
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          _add(day);
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('Add'),
                      ),
                    ],
                  ),
                ),
                if (onDay.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Nothing planned this day.')),
                for (final e in onDay)
                  EntryTile(
                    entry: e,
                    day: day,
                    onTap: () {
                      Navigator.pop(sheetContext);
                      showEntryDetail(context, query, e.id);
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final mode = _mode(wide);
    final query = _query(mode);
    final value = ref.watch(scheduleProvider(query));
    final zone = ref.watch(timezoneProvider);
    final theme = Theme.of(context);

    final modePicker = SegmentedButton<_Mode>(
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(value: _Mode.list, icon: Icon(Icons.view_agenda_outlined), label: Text('List')),
        ButtonSegment(value: _Mode.week, icon: Icon(Icons.view_week_outlined), label: Text('Week')),
        ButtonSegment(value: _Mode.month, icon: Icon(Icons.calendar_view_month_outlined), label: Text('Month')),
      ],
      selected: {mode},
      onSelectionChanged: (s) => setState(() => _chosen = s.first),
    );
    final navigator = mode == _Mode.list
        ? null
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(tooltip: 'Previous', onPressed: () => _shift(mode, -1), icon: const Icon(Icons.chevron_left)),
              Text(_periodLabel(mode), style: theme.textTheme.titleSmall),
              IconButton(tooltip: 'Next', onPressed: () => _shift(mode, 1), icon: const Icon(Icons.chevron_right)),
              TextButton(onPressed: () => setState(() => _anchor = AppClock.today()), child: const Text('Today')),
            ],
          );

    return Scaffold(
      appBar: AppBar(
        title: const Text('My schedule'),
        actions: [
          if (wide) ...[?navigator, const SizedBox(width: 8), modePicker, const SizedBox(width: 12)],
        ],
        // Phones: the switch and date navigation sit in a bar under the title.
        bottom: wide
            ? null
            : PreferredSize(
                preferredSize: Size.fromHeight(mode == _Mode.list ? 56 : 100),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: Column(
                    children: [
                      SizedBox(width: double.infinity, child: modePicker),
                      if (navigator != null) FittedBox(child: navigator),
                    ],
                  ),
                ),
              ),
      ),
      // A compact button on phone calendars so it doesn't hide the grid.
      floatingActionButton: !wide && mode != _Mode.list
          ? FloatingActionButton.small(tooltip: 'Add to schedule', onPressed: _add, child: const Icon(Icons.add))
          : FloatingActionButton.extended(
              onPressed: _add,
              icon: const Icon(Icons.add),
              label: const Text('Add to schedule'),
            ),
      body: Column(
        children: [
          if (AppClock.differsFromDevice)
            Material(
              color: theme.colorScheme.secondaryContainer,
              child: InkWell(
                onTap: () => context.push('/profile'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.public, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Times shown in ${zone.split('/').last.replaceAll('_', ' ')} (${AppClock.offsetLabel()}), '
                          'not this device’s time zone.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Expanded(child: _body(context, mode, query, value)),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, _Mode mode, ScheduleQuery query, AsyncValue<List<ScheduleEntry>> value) {
    return AsyncBody(
      value: value,
      builder: (entries) => switch (mode) {
        _Mode.list => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(scheduleProvider(query));
            await ref.read(scheduleProvider(query).future);
          },
          child: AgendaList(
            entries: entries,
            days: [for (var i = 0; i < _listWeeks * 7; i++) addDays(query.from, i)],
            emptyMessage:
                'Nothing planned in the next $_listWeeks weeks.\n'
                'Add something from a group, or tap “Add to schedule”.',
            onTap: (e) => showEntryDetail(context, query, e.id),
            footer: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: OutlinedButton(
                    onPressed: () => setState(() => _listWeeks += 4),
                    child: const Text('Show 4 more weeks'),
                  ),
                ),
              ),
            ],
          ),
        ),
        _Mode.week => WeekView(
          weekStart: startOfWeek(_anchor),
          entries: entries,
          onTap: (e) => showEntryDetail(context, query, e.id),
          onTapDay: (d) => _openDay(query, entries, d),
        ),
        _Mode.month => MonthView(month: _anchor, entries: entries, onTapDay: (d) => _openDay(query, entries, d)),
      },
    );
  }
}
