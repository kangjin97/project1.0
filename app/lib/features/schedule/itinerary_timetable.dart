import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../data/app_clock.dart';
import '../../data/itinerary.dart';

/// The itinerary as a picture timetable (#96): days as columns (up to 7 per
/// page), hours down the side, each plan a coloured block with its time, title
/// and short location; all-day plans in a band at the top. Drawn the same way
/// for the PNG and the PDF, in fixed print colours (not the app theme).

const _width = 1169.0, _height = 827.0; // A4 landscape proportions
const _scale = 2.0; // pixels per unit: about 200 dpi on A4
const _margin = 32.0, _axis = 44.0, _dayHeader = 30.0, _top = 92.0, _footer = 26.0;
const _ink = Color(0xFF1B1B1F), _muted = Color(0xFF5B5D67), _line = Color(0xFFDADCE4);
const _palette = [
  Color(0xFFD7E3FF), Color(0xFFFFE0B2), Color(0xFFD5F5E3), Color(0xFFF8D7E8),
  Color(0xFFE6DEFF), Color(0xFFD9F2F7), Color(0xFFFFF4C2), Color(0xFFE3F2C9),
];

/// One PNG per page of up to 7 days.
Future<List<Uint8List>> timetablePages(Itinerary itinerary) async {
  final pages = <Uint8List>[];
  final days = itinerary.days;
  for (var i = 0; i < days.length; i += 7) {
    final image = await _drawPage(itinerary, days.sublist(i, min(i + 7, days.length)));
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    pages.add(bytes!.buffer.asUint8List());
    image.dispose();
  }
  return pages;
}

/// The whole range as one picture: pages stacked when it's more than a week.
Future<Uint8List> timetablePng(Itinerary itinerary) async {
  final pages = await timetablePages(itinerary);
  if (pages.length == 1) return pages.single;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final w = (_width * _scale).round(), h = (_height * _scale).round();
  for (var i = 0; i < pages.length; i++) {
    final codec = await ui.instantiateImageCodec(pages[i]);
    final frame = await codec.getNextFrame();
    canvas.drawImage(frame.image, Offset(0, i * h.toDouble()), Paint());
    frame.image.dispose();
  }
  final image = await recorder.endRecording().toImage(w, h * pages.length);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return bytes!.buffer.asUint8List();
}

/// A4 landscape PDF, one page per week of the range.
Future<Uint8List> timetablePdf(Itinerary itinerary) async {
  final doc = pw.Document(title: '${itinerary.groupName} · ${itinerary.rangeLabel}', creator: 'EasyPlan');
  for (final png in await timetablePages(itinerary)) {
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: pw.EdgeInsets.zero,
      build: (_) => pw.Image(pw.MemoryImage(png), fit: pw.BoxFit.contain),
    ));
  }
  return doc.save();
}

Color colourFor(String key) => _palette[key.codeUnits.fold(0, (a, c) => (a * 31 + c) & 0x7fffffff) % _palette.length];

Future<ui.Image> _drawPage(Itinerary it, List<ItineraryDay> days) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(_scale);
  canvas.drawRect(const Rect.fromLTWH(0, 0, _width, _height), Paint()..color = const Color(0xFFFFFFFF));

  // Header and footer.
  _text(canvas, it.groupName, const Offset(_margin, _margin - 4), size: 22, weight: FontWeight.w700, maxWidth: 700);
  final range = DateFormat('EEE d MMM').format(days.first.date) +
      (days.length > 1 ? ' – ${DateFormat('EEE d MMM y').format(days.last.date)}' : DateFormat(' y').format(days.first.date));
  _text(canvas, range, const Offset(_margin, _margin + 26), size: 13, colour: _muted, maxWidth: 700);
  _text(canvas, 'Times in ${AppClock.zoneName} · EasyPlan', Offset(_margin, _height - _footer + 4),
      size: 10, colour: _muted, maxWidth: 600);

  final timed = [for (final d in days) for (final i in d.items) if (!i.allDay) (d, i)];
  final allDayLanes = days.map((d) => d.items.where((i) => i.allDay).length).fold(0, max);
  final allDayBand = allDayLanes == 0 ? 0.0 : allDayLanes * 24.0 + 8;

  // Hours shown: around the plans, at least 8:00–20:00 when there's room.
  var firstHour = 8, lastHour = 20;
  for (final (d, i) in timed) {
    final (s, e) = i.minutesOn(d.date);
    firstHour = min(firstHour, s ~/ 60);
    lastHour = max(lastHour, (e + 59) ~/ 60);
  }
  lastHour = min(lastHour, 24);

  // Fewer days leave wide columns: use bigger text there.
  final textScale = days.length <= 2 ? 1.4 : (days.length <= 4 ? 1.2 : 1.0);
  final gridLeft = _margin + _axis;
  final colW = (_width - _margin - gridLeft) / days.length;
  final headerTop = _top;
  final allDayTop = headerTop + _dayHeader;
  final gridTop = allDayTop + allDayBand;
  final gridBottom = _height - _footer - 8;
  final hourH = (gridBottom - gridTop) / (lastHour - firstHour);
  final line = Paint()
    ..color = _line
    ..strokeWidth = 1;

  // Day headers and column lines.
  for (var c = 0; c < days.length; c++) {
    final x = gridLeft + c * colW;
    _text(canvas, DateFormat('EEE d MMM').format(days[c].date), Offset(x + 6, headerTop + 6),
        size: 13, weight: FontWeight.w600, maxWidth: colW - 12);
    canvas.drawLine(Offset(x, headerTop), Offset(x, gridBottom), line);
  }
  canvas.drawLine(Offset(_width - _margin, headerTop), Offset(_width - _margin, gridBottom), line);

  // Hour lines.
  for (var h = firstHour; h <= lastHour; h++) {
    final y = gridTop + (h - firstHour) * hourH;
    canvas.drawLine(Offset(gridLeft, y), Offset(_width - _margin, y), line);
    if (h < lastHour) _text(canvas, DateFormat('h a').format(DateTime(2000, 1, 1, h)), Offset(_margin, y + 2), size: 10, colour: _muted);
  }

  // All-day band.
  for (var c = 0; c < days.length; c++) {
    final allDay = days[c].items.where((i) => i.allDay).toList();
    for (var l = 0; l < allDay.length; l++) {
      final r = Rect.fromLTWH(gridLeft + c * colW + 3, allDayTop + 4 + l * 24, colW - 6, 20);
      _block(canvas, r, allDay[l], [allDay[l].title], textScale: min(textScale, 1.2));
    }
  }

  // Timed plans; overlapping ones share the column side by side.
  for (var c = 0; c < days.length; c++) {
    final day = days[c];
    final items = [for (final i in day.items) if (!i.allDay) (i, i.minutesOn(day.date))];
    for (final (item, (s, e), lane, lanes) in _lanes(items)) {
      final top = gridTop + (s / 60 - firstHour) * hourH;
      final bottom = gridTop + (max(e, s + 20) / 60 - firstHour) * hourH;
      final laneW = (colW - 6) / lanes;
      final r = Rect.fromLTRB(gridLeft + c * colW + 3 + lane * laneW, top + 1, gridLeft + c * colW + 3 + (lane + 1) * laneW - 2,
          min(bottom - 1, gridBottom));
      _block(canvas, r, item, [item.title, item.timeLabel(day.date), ?item.shortPlace], textScale: textScale);
    }
  }

  if (timed.isEmpty && allDayLanes == 0) {
    _text(canvas, 'Nothing planned on these days.', Offset(gridLeft + 12, gridTop + 12), size: 14, colour: _muted);
  }

  return recorder.endRecording().toImage((_width * _scale).round(), (_height * _scale).round());
}

/// Lays overlapping plans out in lanes: (item, minutes, lane, lanes in its group).
List<(ItineraryItem, (int, int), int, int)> _lanes(List<(ItineraryItem, (int, int))> items) {
  final sorted = [...items]..sort((a, b) => a.$2.$1.compareTo(b.$2.$1));
  final out = <(ItineraryItem, (int, int), int, int)>[];
  var group = <(ItineraryItem, (int, int), int)>[];
  var groupEnd = -1;
  void flush() {
    final lanes = group.map((g) => g.$3).fold(0, max) + 1;
    out.addAll([for (final g in group) (g.$1, g.$2, g.$3, lanes)]);
    group = [];
  }

  for (final (item, (s, e)) in sorted) {
    if (s >= groupEnd && group.isNotEmpty) flush();
    final laneEnds = <int, int>{};
    for (final g in group) {
      laneEnds[g.$3] = max(laneEnds[g.$3] ?? 0, g.$2.$2);
    }
    var lane = 0;
    while ((laneEnds[lane] ?? -1) > s) {
      lane++;
    }
    group.add((item, (s, e), lane));
    groupEnd = max(groupEnd, e);
  }
  if (group.isNotEmpty) flush();
  return out;
}

void _block(Canvas canvas, Rect r, ItineraryItem item, List<String> lines, {double textScale = 1}) {
  final rr = RRect.fromRectAndRadius(r, const Radius.circular(5));
  // One colour per plan (the same activity keeps its colour across days).
  canvas.drawRRect(rr, Paint()..color = colourFor(item.entry.activityId ?? item.title));
  canvas.save();
  canvas.clipRRect(rr);
  var y = r.top + 3;
  for (var i = 0; i < lines.length; i++) {
    // The title always shows (clipped if it must); other lines only when they fit whole.
    final h = _text(canvas, lines[i], Offset(r.left + 5, y),
        size: (i == 0 ? 11.5 : 10) * textScale, weight: i == 0 ? FontWeight.w600 : FontWeight.w400,
        colour: i == 0 ? _ink : _muted, maxWidth: r.width - 10, bottom: i == 0 ? null : r.bottom - 2);
    if (h == 0) break;
    y += h;
  }
  canvas.restore();
}

/// Draws one line of text (ellipsis when too wide) and returns its height, or
/// draws nothing and returns 0 when it would end below [bottom].
double _text(Canvas canvas, String text, Offset at,
    {double size = 12,
    FontWeight weight = FontWeight.w400,
    Color colour = _ink,
    double maxWidth = 400,
    double? bottom}) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: TextStyle(fontSize: size, fontWeight: weight, color: colour, height: 1.25)),
    textDirection: ui.TextDirection.ltr,
    maxLines: 1,
    ellipsis: '…',
  )..layout(maxWidth: max(0, maxWidth));
  final h = painter.height;
  if (bottom != null && at.dy + h > bottom) {
    painter.dispose();
    return 0;
  }
  painter.paint(canvas, at);
  painter.dispose();
  return h;
}
