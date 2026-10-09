import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/app_clock.dart';
import '../../data/schedule_models.dart';
import 'schedule_widgets.dart';

const _hourHeight = 48.0;

/// Seven-day grid: all-day row on top, timed entries placed by hour below.
class WeekView extends StatefulWidget {
  const WeekView({super.key, required this.weekStart, required this.entries, required this.onTap, required this.onTapDay});

  final DateTime weekStart;
  final List<ScheduleEntry> entries;
  final ValueChanged<ScheduleEntry> onTap;
  final ValueChanged<DateTime> onTapDay;

  @override
  State<WeekView> createState() => _WeekViewState();
}

class _WeekViewState extends State<WeekView> {
  // Start the day at 8am; earlier hours are a scroll away.
  final _scroll = ScrollController(initialScrollOffset: 8 * _hourHeight);

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Phones get a slimmer hour gutter so the seven columns keep usable width.
    final narrow = MediaQuery.sizeOf(context).width < 600;
    final gutter = narrow ? 36.0 : 56.0;
    final days = [for (var i = 0; i < 7; i++) addDays(widget.weekStart, i)];
    final today = AppClock.today();

    // All-day row: all-day entries, plus full middle days of multi-day timed entries.
    List<ScheduleEntry> allDayOn(DateTime d) => widget.entries
        .where((e) => e.occursOn(d) && (e.allDay || (!isSameDay(e.startAt!, d) && !isSameDay(e.endAt!, d))))
        .toList();
    final allDayRows = days.map((d) => allDayOn(d).length).fold(0, math.max);

    return Column(
      children: [
        // Day headers
        Row(
          children: [
            SizedBox(width: gutter),
            for (final d in days)
              Expanded(
                child: InkWell(
                  onTap: () => widget.onTapDay(d),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      children: [
                        Text(DateFormat(narrow ? 'E' : 'EEE').format(d).substring(0, narrow ? 1 : null),
                            style: theme.textTheme.labelMedium),
                        const SizedBox(height: 2),
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isSameDay(d, today) ? theme.colorScheme.primary : null,
                          ),
                          child: Text(
                            '${d.day}',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: isSameDay(d, today) ? theme.colorScheme.onPrimary : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        if (allDayRows > 0)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: gutter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 6, right: 4),
                  child: Text(narrow ? 'All' : 'All day', textAlign: TextAlign.right, style: theme.textTheme.labelSmall),
                ),
              ),
              for (final d in days)
                Expanded(
                  child: Column(
                    children: [
                      for (final e in allDayOn(d))
                        _Block(entry: e, compact: true, onTap: () => widget.onTap(e)),
                    ],
                  ),
                ),
            ],
          ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            controller: _scroll,
            child: SizedBox(
              height: 24 * _hourHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: gutter,
                    child: Stack(
                      children: [
                        for (var h = 1; h < 24; h++)
                          Positioned(
                            top: h * _hourHeight - 7,
                            right: narrow ? 4 : 8,
                            child: Text(DateFormat(narrow ? 'ha' : 'h a').format(DateTime(2000, 1, 1, h)),
                                style: theme.textTheme.labelSmall),
                          ),
                      ],
                    ),
                  ),
                  for (final d in days)
                    Expanded(child: _DayColumn(day: d, entries: widget.entries, onTap: widget.onTap)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// One day's timed entries, side by side where they overlap.
class _DayColumn extends StatelessWidget {
  const _DayColumn({required this.day, required this.entries, required this.onTap});

  final DateTime day;
  final List<ScheduleEntry> entries;
  final ValueChanged<ScheduleEntry> onTap;

  @override
  Widget build(BuildContext context) {
    final next = addDays(day, 1);
    final dayStart = AppClock.at(day.year, day.month, day.day), dayEnd = AppClock.at(next.year, next.month, next.day);
    // Timed segments that fall within this day (multi-day middles go in the all-day row).
    final segments = <({ScheduleEntry e, DateTime start, DateTime end})>[
      for (final e in entries)
        if (!e.allDay && e.startAt != null && e.occursOn(day) && (isSameDay(e.startAt!, day) || isSameDay(e.endAt!, day)))
          (
            e: e,
            start: e.startAt!.isBefore(dayStart) ? dayStart : e.startAt!,
            end: e.endAt!.isAfter(dayEnd) ? dayEnd : e.endAt!,
          ),
    ]..sort((a, b) => a.start.compareTo(b.start));

    // Greedy columns: each segment goes in the first column that's free.
    final columnEnds = <DateTime>[];
    final columnOf = <int>[];
    for (final s in segments) {
      var c = columnEnds.indexWhere((end) => !end.isAfter(s.start));
      if (c < 0) {
        columnEnds.add(s.end);
        c = columnEnds.length - 1;
      } else {
        columnEnds[c] = s.end;
      }
      columnOf.add(c);
    }
    final columns = math.max(1, columnEnds.length);
    final lineColor = Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth / columns;
        double y(DateTime t) => (t.difference(dayStart).inMinutes) * _hourHeight / 60;
        return Container(
          decoration: BoxDecoration(border: Border(left: BorderSide(color: lineColor))),
          child: Stack(
            children: [
              for (var h = 1; h < 24; h++)
                Positioned(top: h * _hourHeight, left: 0, right: 0, child: Divider(height: 1, color: lineColor)),
              for (var i = 0; i < segments.length; i++)
                Positioned(
                  top: y(segments[i].start),
                  height: math.max(22, y(segments[i].end) - y(segments[i].start)),
                  left: columnOf[i] * width,
                  width: width,
                  child: _Block(entry: segments[i].e, onTap: () => onTap(segments[i].e)),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({required this.entry, required this.onTap, this.compact = false});

  final ScheduleEntry entry;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mine = entry.iAmIn;
    final bg = mine ? scheme.primaryContainer : scheme.surfaceContainerHighest;
    final fg = mine ? scheme.onPrimaryContainer : scheme.onSurfaceVariant;
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(color: fg);
    return Padding(
      padding: const EdgeInsets.all(1),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: entry.iHaveClash
                ? BoxDecoration(border: Border(left: BorderSide(color: scheme.error, width: 3)))
                : null,
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
            alignment: Alignment.topLeft,
            child: LayoutBuilder(builder: (context, c) {
              final tight = c.maxWidth < 64;
              return Text(
                compact || tight || entry.startAt == null
                    ? entry.displayTitle
                    : '${entry.displayTitle}\n${formatTime(entry.startAt!)}',
                style: style?.copyWith(fontWeight: FontWeight.w600, fontSize: tight ? 10 : null),
                maxLines: compact ? 1 : 4,
                overflow: TextOverflow.ellipsis,
              );
            }),
          ),
        ),
      ),
    );
  }
}

/// Month grid (six weeks from the Monday before the 1st).
class MonthView extends StatelessWidget {
  const MonthView({super.key, required this.month, required this.entries, required this.onTapDay});

  final DateTime month;
  final List<ScheduleEntry> entries;
  final ValueChanged<DateTime> onTapDay;

  static DateTime gridStart(DateTime month) => startOfWeek(DateTime(month.year, month.month, 1));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final start = gridStart(month);
    final today = AppClock.today();
    final lineColor = theme.colorScheme.outlineVariant.withValues(alpha: 0.6);
    return Column(
      children: [
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(DateFormat(MediaQuery.sizeOf(context).width < 600 ? 'E' : 'EEE').format(addDays(start, i)),
                      textAlign: TextAlign.center, style: theme.textTheme.labelMedium),
                ),
              ),
          ],
        ),
        for (var w = 0; w < 6; w++)
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: Builder(builder: (context) {
                      final d = addDays(start, w * 7 + i);
                      final onDay = entries.where((e) => e.occursOn(d)).toList();
                      final inMonth = d.month == month.month;
                      return InkWell(
                        onTap: () => onTapDay(d),
                        child: Container(
                          decoration: BoxDecoration(border: Border.all(color: lineColor, width: 0.5)),
                          padding: const EdgeInsets.all(4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isSameDay(d, today) ? theme.colorScheme.primary : null,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  '${d.day}',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: isSameDay(d, today)
                                        ? theme.colorScheme.onPrimary
                                        : inMonth
                                            ? null
                                            : theme.colorScheme.outline,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: LayoutBuilder(builder: (context, c) {
                                  if (c.maxWidth < 72) {
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Wrap(
                                        spacing: 3,
                                        runSpacing: 3,
                                        children: [
                                          for (final e in onDay.take(6))
                                            Container(
                                              width: 7,
                                              height: 7,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: e.iHaveClash
                                                    ? theme.colorScheme.error
                                                    : e.iAmIn
                                                        ? theme.colorScheme.primary
                                                        : theme.colorScheme.outline,
                                              ),
                                            ),
                                        ],
                                      ),
                                    );
                                  }
                                  final fits = math.max(0, (c.maxHeight / 18).floor());
                                  final shown = onDay.length > fits ? math.max(0, fits - 1) : onDay.length;
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      for (final e in onDay.take(shown))
                                        Text(
                                          '${e.iHaveClash ? '⚠ ' : ''}${e.displayTitle}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.labelSmall?.copyWith(
                                            color: e.iAmIn ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                                            fontWeight: e.iAmIn ? FontWeight.w600 : null,
                                          ),
                                        ),
                                      if (onDay.length > shown)
                                        Text('+${onDay.length - shown} more', style: theme.textTheme.labelSmall),
                                    ],
                                  );
                                }),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
