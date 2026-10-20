import 'package:excel/excel.dart';
import 'package:intl/intl.dart';

import 'models.dart';
import 'places_repository.dart';
import 'schedule_models.dart';

/// One plan in an exported itinerary (#96), with what its activity adds.
class ItineraryItem {
  ItineraryItem({
    required this.entry,
    required this.title,
    this.typeName,
    this.location,
    this.placeId,
    this.activity,
    required this.people,
  });

  final ScheduleEntry entry;
  final String title;
  final String? typeName;
  final String? location;
  final String? placeId;

  /// Null for events (no activity yet) and activities that are no longer shared.
  final Activity? activity;

  /// Who's going, by name.
  final List<String> people;

  bool get allDay => entry.allDay;
  DateTime? get start => entry.startAt;
  DateTime? get end => entry.endAt;
  String? get price => activity?.priceLabel;
  String? get url => (activity?.url?.trim().isEmpty ?? true) ? null : activity!.url!.trim();
  String? get description => (activity?.description?.trim().isEmpty ?? true) ? null : activity!.description!.trim();

  /// Google Maps link for the location (the exact place when one was picked).
  Uri? get mapsUri => location == null ? null : googleMapsUri(location!, placeId: placeId);

  /// When it happens on [day], worded like the app's schedule: "10:00 AM – 12:30 PM",
  /// "All day", or "From 11:00 PM" / "Until 1:00 AM" for a plan across midnight.
  String timeLabel(DateTime day) {
    if (allDay) return 'All day';
    final f = DateFormat('h:mm a');
    final s = start!, e = end!;
    if (isSameDay(s, e)) return '${f.format(s)} – ${f.format(e)}';
    if (isSameDay(day, s)) return 'From ${f.format(s)}';
    if (isSameDay(day, e)) return 'Until ${f.format(e)}';
    return 'All day';
  }

  /// Minutes from midnight on [day] when the plan starts and ends there,
  /// clipped to the day (for timetables).
  (int, int) minutesOn(DateTime day) {
    final dayStart = dateOnly(day);
    final s = start!.isBefore(dayStart) ? 0 : start!.difference(dayStart).inMinutes;
    final e = end!.difference(dayStart).inMinutes;
    return (s.clamp(0, 24 * 60), e.clamp(0, 24 * 60));
  }
}

class ItineraryDay {
  ItineraryDay(this.date, this.items);

  final DateTime date;

  /// All-day plans first, then by start time.
  final List<ItineraryItem> items;
}

/// A group's plans for a date range, ready to export (#96).
class Itinerary {
  Itinerary({required this.groupName, required this.from, required this.to, required this.days});

  final String groupName;
  final DateTime from;
  final DateTime to;
  final List<ItineraryDay> days;

  bool get isEmpty => days.every((d) => d.items.isEmpty);
  int get planCount => {for (final d in days) for (final i in d.items) i.entry.id}.length;

  /// "Sat 25 – Sun 26 Oct 2026", "Fri 31 Oct – Sun 2 Nov 2026", "Sat 25 Oct 2026".
  String get rangeLabel {
    if (isSameDay(from, to)) return DateFormat('EEE d MMM y').format(from);
    final sameMonth = from.month == to.month && from.year == to.year;
    final sameYear = from.year == to.year;
    final left = DateFormat(sameMonth ? 'EEE d' : (sameYear ? 'EEE d MMM' : 'EEE d MMM y')).format(from);
    return '$left – ${DateFormat('EEE d MMM y').format(to)}';
  }

  /// Plans from [entries] (one group's schedule) that fall on days between
  /// [from] and [to]. [activities] add type, location, price and links. Plans
  /// with no date are left out.
  factory Itinerary.build({
    required String groupName,
    required DateTime from,
    required DateTime to,
    required List<ScheduleEntry> entries,
    required List<GroupActivity> activities,
  }) {
    final byActivity = {for (final ga in activities) ga.activityId: ga};
    final days = <ItineraryDay>[];
    for (var d = dateOnly(from); !d.isAfter(to); d = addDays(d, 1)) {
      final items = [
        for (final e in entries)
          if (!e.isUnscheduled && e.occursOn(d)) _item(e, byActivity[e.activityId]),
      ]..sort((a, b) {
          if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
          if (a.allDay) return a.title.toLowerCase().compareTo(b.title.toLowerCase());
          return a.start!.compareTo(b.start!);
        });
      days.add(ItineraryDay(d, items));
    }
    return Itinerary(groupName: groupName, from: dateOnly(from), to: dateOnly(to), days: days);
  }

  static ItineraryItem _item(ScheduleEntry e, GroupActivity? ga) => ItineraryItem(
        entry: e,
        title: e.displayTitle,
        typeName: ga?.typeName,
        location: ga?.activity.location,
        placeId: ga?.activity.placeId,
        activity: ga?.activity,
        people: [for (final p in e.participants) p.label],
      );

  /// A day-by-day summary to paste into a group chat. Days without plans are
  /// skipped.
  String chatText() {
    final b = StringBuffer('📅 $groupName · $rangeLabel\n');
    for (final day in days) {
      if (day.items.isEmpty) continue;
      b.write('\n*${DateFormat('EEE d MMM').format(day.date)}*\n');
      for (final i in day.items) {
        b.write('• ${i.timeLabel(day.date)} ${i.title}');
        if (i.location != null) b.write(' — ${i.location}');
        if (i.price != null) b.write(' (${i.price})');
        b.write('\n');
      }
    }
    if (isEmpty) b.write('\nNothing planned yet.\n');
    return b.toString().trimRight();
  }

  /// Rough cost per person across [items]: the low and high ends of their
  /// price ranges, per currency. Plans without a price don't count.
  static Map<String, (double, double)> costOf(Iterable<ItineraryItem> items) {
    final totals = <String, (double, double)>{};
    for (final i in items) {
      final a = i.activity;
      if (a == null || (a.priceMin == null && a.priceMax == null)) continue;
      final lo = a.priceMin ?? a.priceMax!, hi = a.priceMax ?? a.priceMin!;
      final (tLo, tHi) = totals[a.currency] ?? (0.0, 0.0);
      totals[a.currency] = (tLo + lo, tHi + hi);
    }
    return totals;
  }

  static String costLabel(Map<String, (double, double)> totals) {
    if (totals.isEmpty) return '';
    String fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
    return [
      for (final MapEntry(key: currency, value: (lo, hi)) in totals.entries)
        lo == hi ? '$currency ${fmt(lo)}' : '$currency ${fmt(lo)}–${fmt(hi)}',
    ].join(' + ');
  }

  /// The detailed itinerary as an Excel workbook: a summary sheet, then one
  /// sheet per day with plans.
  List<int> toExcel() {
    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet()!;
    final bold = CellStyle(bold: true);
    final title = CellStyle(bold: true, fontSize: 14);

    void row(Sheet s, List<CellValue?> values, {CellStyle? style}) {
      s.appendRow(values);
      if (style == null) return;
      final r = s.maxRows - 1;
      for (var c = 0; c < values.length; c++) {
        s.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r)).cellStyle = style;
      }
    }

    String link(Uri u, String text) => 'HYPERLINK("${u.toString().replaceAll('"', '""')}","$text")';

    // Summary.
    final summary = excel['Summary'];
    row(summary, [TextCellValue('$groupName · $rangeLabel')], style: title);
    row(summary, [TextCellValue('Exported from EasyPlan. Costs are per person, from the activities\' price ranges.')]);
    row(summary, []);
    row(summary, [TextCellValue('Day'), TextCellValue('Plans'), TextCellValue('Estimated cost')], style: bold);
    for (final day in days) {
      row(summary, [
        TextCellValue(DateFormat('EEE d MMM y').format(day.date)),
        IntCellValue(day.items.length),
        TextCellValue(costLabel(costOf(day.items))),
      ]);
    }
    row(summary, [
      TextCellValue('Total'),
      IntCellValue(planCount),
      TextCellValue(costLabel(costOf({for (final d in days) for (final i in d.items) i.entry.id: i}.values))),
    ], style: bold);
    summary.setColumnWidth(0, 22);
    summary.setColumnWidth(2, 28);

    // One sheet per day with plans.
    const headers = ['Time', 'Plan', 'Type', 'Location', 'Map', 'Price', 'Who\'s going', 'Link', 'Description', 'Notes'];
    final used = <String>{};
    for (final day in days) {
      if (day.items.isEmpty) continue;
      var name = DateFormat('EEE d MMM').format(day.date);
      if (!used.add(name)) name = DateFormat('d MMM y').format(day.date);
      final s = excel[name];
      row(s, [TextCellValue(DateFormat('EEEE d MMMM y').format(day.date))], style: title);
      row(s, [for (final h in headers) TextCellValue(h)], style: bold);
      for (final i in day.items) {
        row(s, [
          TextCellValue(i.timeLabel(day.date)),
          TextCellValue(i.title),
          i.typeName == null ? null : TextCellValue(i.typeName!),
          i.location == null ? null : TextCellValue(i.location!),
          i.mapsUri == null ? null : FormulaCellValue(link(i.mapsUri!, 'Open map')),
          i.price == null ? null : TextCellValue(i.price!),
          TextCellValue(i.people.join(', ')),
          i.url == null ? null : FormulaCellValue(link(Uri.parse(i.url!), 'Open link')),
          i.description == null ? null : TextCellValue(i.description!),
          null,
        ]);
      }
      const widths = [14.0, 30.0, 14.0, 36.0, 10.0, 16.0, 28.0, 10.0, 48.0, 24.0];
      for (var c = 0; c < widths.length; c++) {
        s.setColumnWidth(c, widths[c]);
      }
    }

    excel.delete(defaultSheet);
    excel.setDefaultSheet('Summary');
    // encode(), not save(): on the web save() also starts its own download.
    return excel.encode()!;
  }
}
