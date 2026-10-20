import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/activities_repository.dart';
import '../../data/app_clock.dart';
import '../../data/calendar_export.dart';
import '../../data/export/save_file.dart';
import '../../data/groups_repository.dart';
import '../../data/itinerary.dart';
import '../../data/schedule_models.dart';
import '../../data/schedule_repository.dart';
import '../../widgets/dialogs.dart';
import '../schedule/itinerary_timetable.dart';

enum ItineraryFormat {
  excel('Excel itinerary', 'Every detail: times, places with map links, prices, who’s going. A sheet per day and a cost summary.',
      Icons.table_chart_outlined),
  pdf('PDF timetable', 'A printable picture of the days, with each plan as a block. Minimal text.', Icons.picture_as_pdf_outlined),
  png('Image', 'The timetable as one picture, for sending in a chat.', Icons.image_outlined),
  ics('Calendar file', 'Add these plans to Google Calendar, Apple Calendar or Outlook in one go. They’re copies: later changes don’t follow.',
      Icons.event_outlined),
  text('Text for a chat', 'A day-by-day summary copied for you to paste.', Icons.chat_outlined);

  const ItineraryFormat(this.label, this.description, this.icon);

  final String label;
  final String description;
  final IconData icon;
}

/// Export a group's plans for a date range (#96).
Future<void> showItineraryExport(BuildContext context, {required String groupId}) => showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ExportSheet(groupId: groupId),
    );

/// The coming weekend (today if it's already Saturday or Sunday).
DateTimeRange comingWeekend(DateTime today) {
  final sat = today.weekday == DateTime.sunday ? addDays(today, -1) : addDays(today, (DateTime.saturday - today.weekday) % 7);
  return DateTimeRange(start: sat, end: addDays(sat, 1));
}

/// "Crew itinerary 2026-10-24 to 2026-10-25.xlsx", safe for any file system.
String itineraryFileName(String groupName, DateTime from, DateTime to, String extension) {
  final safe = groupName.replaceAll(RegExp(r'[\\/:*?"<>|]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  final dates = isSameDay(from, to) ? isoDate(from) : '${isoDate(from)} to ${isoDate(to)}';
  return '${safe.isEmpty ? 'EasyPlan' : safe} itinerary $dates.$extension';
}

class _ExportSheet extends ConsumerStatefulWidget {
  const _ExportSheet({required this.groupId});

  final String groupId;

  @override
  ConsumerState<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends ConsumerState<_ExportSheet> {
  /// Long ranges make huge files; a trip rarely needs more.
  static const _maxDays = 62;

  late DateTimeRange _range = comingWeekend(AppClock.today());
  ItineraryFormat _format = ItineraryFormat.excel;
  bool _busy = false;
  String? _note;

  Future<void> _chooseDates() async {
    final today = AppClock.today();
    final picked = await showDateRangePicker(
      context: context,
      useRootNavigator: true,
      firstDate: addDays(today, -365),
      lastDate: addDays(today, 730),
      initialDateRange: _range,
      helpText: 'Itinerary dates',
    );
    if (picked == null) return;
    if (picked.duration.inDays + 1 > _maxDays) {
      setState(() => _note = 'Choose at most $_maxDays days.');
      return;
    }
    setState(() {
      _range = DateTimeRange(start: dateOnly(picked.start), end: dateOnly(picked.end));
      _note = null;
    });
  }

  void _preset(DateTimeRange r) => setState(() {
        _range = r;
        _note = null;
      });

  Future<void> _export() async {
    setState(() {
      _busy = true;
      _note = null;
    });
    try {
      final from = _range.start, to = _range.end;
      final group = await ref.read(groupProvider(widget.groupId).future);
      final entries = await ref.read(scheduleRepositoryProvider)
          .list((from: from, to: to, groupId: widget.groupId, includeUnscheduled: false));
      final activities = await ref.read(groupActivitiesProvider(widget.groupId).future);
      final it = Itinerary.build(groupName: group.name, from: from, to: to, entries: entries, activities: activities);
      if (it.isEmpty) {
        setState(() => _note = 'Nothing planned in ${group.name} on ${it.rangeLabel}.');
        return;
      }
      String name(String ext) => itineraryFileName(group.name, from, to, ext);
      switch (_format) {
        case ItineraryFormat.excel:
          await saveFile(Uint8List.fromList(it.toExcel()),
              name: name('xlsx'), mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
        case ItineraryFormat.pdf:
          await saveFile(await timetablePdf(it), name: name('pdf'), mimeType: 'application/pdf');
        case ItineraryFormat.png:
          await saveFile(await timetablePng(it), name: name('png'), mimeType: 'image/png');
        case ItineraryFormat.ics:
          await saveFile(Uint8List.fromList(utf8.encode(toIcs(it))), name: name('ics'), mimeType: 'text/calendar');
        case ItineraryFormat.text:
          await Clipboard.setData(ClipboardData(text: it.chatText()));
      }
      if (!mounted) return;
      Navigator.pop(context);
      showMessage(
          context,
          _format == ItineraryFormat.text
              ? 'Copied ${it.planCount} plans. Paste them into your chat.'
              : _format == ItineraryFormat.ics
                  ? 'Exported ${it.planCount} plans. Open the file to add them, or in Google Calendar on a computer use Settings → Import.'
                  : 'Exported ${it.planCount} plans.');
    } catch (e) {
      if (mounted) setState(() => _note = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = AppClock.today();
    final weekend = comingWeekend(today);
    final next7 = DateTimeRange(start: today, end: addDays(today, 6));
    bool isRange(DateTimeRange r) => isSameDay(r.start, _range.start) && isSameDay(r.end, _range.end);
    final days = _range.duration.inDays + 1;
    final rangeText = isSameDay(_range.start, _range.end)
        ? DateFormat('EEE d MMM y').format(_range.start)
        : '${DateFormat('EEE d MMM').format(_range.start)} – ${DateFormat('EEE d MMM y').format(_range.end)}';

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Export itinerary', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('The group’s plans on the days you choose. Ideas without a date aren’t included.',
                style: theme.textTheme.bodySmall),
            const SizedBox(height: 16),
            Text('Days', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(label: const Text('This weekend'), selected: isRange(weekend), onSelected: (_) => _preset(weekend)),
                ChoiceChip(label: const Text('Next 7 days'), selected: isRange(next7), onSelected: (_) => _preset(next7)),
                ActionChip(
                  avatar: const Icon(Icons.date_range, size: 18),
                  label: const Text('Choose dates…'),
                  onPressed: _busy ? null : _chooseDates,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('$rangeText · $days ${days == 1 ? 'day' : 'days'}', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 16),
            Text('Format', style: theme.textTheme.labelLarge),
            RadioGroup<ItineraryFormat>(
              groupValue: _format,
              onChanged: (f) => setState(() => _format = f ?? _format),
              child: Column(
                children: [
                  for (final f in ItineraryFormat.values)
                    RadioListTile<ItineraryFormat>(
                      value: f,
                      contentPadding: EdgeInsets.zero,
                      secondary: Icon(f.icon),
                      title: Text(f.label),
                      subtitle: Text(f.description),
                    ),
                ],
              ),
            ),
            if (_note != null) ...[
              const SizedBox(height: 8),
              Text(_note!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _export,
              icon: _busy
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(_format == ItineraryFormat.text ? Icons.copy : Icons.download),
              label: Text(_format == ItineraryFormat.text ? 'Copy text' : 'Export'),
            ),
          ],
        ),
      ),
    );
  }
}
