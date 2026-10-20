import 'dart:convert';

import 'package:intl/intl.dart';

import '../config.dart';
import 'itinerary.dart';
import 'schedule_models.dart';

/// Getting plans into people's own calendars (#97), with no calendar account
/// permission: a Google Calendar link per plan, and an .ics file for many.
/// Copies don't follow later changes to the plan.

/// Where the plan lives in EasyPlan (the group page), for the event's notes.
String planLink(ScheduleEntry e) => '${AppConfig.appUrl}/groups/${e.groupId}';

/// The event's notes: who's going, price, the activity's link and description,
/// and a link back to the group in EasyPlan.
String calendarNotes(ItineraryItem i) => [
      'Planned in ${i.entry.groupName} on EasyPlan.',
      if (i.people.isNotEmpty) 'Going: ${i.people.join(', ')}',
      if (i.price != null) 'Price: ${i.price}',
      if (i.url != null) i.url!,
      if (i.description != null) i.description!,
      planLink(i.entry),
    ].join('\n');

final _utc = DateFormat("yyyyMMdd'T'HHmmss'Z'");
final _day = DateFormat('yyyyMMdd');

/// Opens Google Calendar's "new event" page with the plan filled in; the person
/// saves it there. Null for plans with no date.
Uri? googleCalendarUri(ItineraryItem i) {
  final e = i.entry;
  final String dates;
  if (e.allDay && e.date != null) {
    dates = '${_day.format(e.date!)}/${_day.format(addDays(e.date!, 1))}';
  } else if (e.startAt != null && e.endAt != null) {
    dates = '${_utc.format(e.startAt!.toUtc())}/${_utc.format(e.endAt!.toUtc())}';
  } else {
    return null;
  }
  return Uri.https('calendar.google.com', '/calendar/render', {
    'action': 'TEMPLATE',
    'text': i.title,
    'dates': dates,
    'details': calendarNotes(i),
    'location': ?i.location,
  });
}

/// The plans as an iCalendar file (RFC 5545) that Google Calendar, Apple
/// Calendar and Outlook import. Each plan keeps its EasyPlan ID as the UID, so
/// calendars that support it update rather than duplicate on re-import.
String toIcs(Itinerary itinerary, {DateTime? now}) {
  final stamp = _utc.format((now ?? DateTime.now()).toUtc());
  final lines = <String>[
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//EasyPlan//Itinerary//EN',
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH',
    'X-WR-CALNAME:${_escape('${itinerary.groupName} · ${itinerary.rangeLabel}')}',
  ];
  final seen = <String>{};
  for (final day in itinerary.days) {
    for (final i in day.items) {
      final e = i.entry;
      if (!seen.add(e.id)) continue; // plans across midnight appear on two days
      lines.addAll([
        'BEGIN:VEVENT',
        'UID:${e.id}@easyplan',
        'DTSTAMP:$stamp',
        if (e.allDay) ...[
          'DTSTART;VALUE=DATE:${_day.format(e.date!)}',
          'DTEND;VALUE=DATE:${_day.format(addDays(e.date!, 1))}',
        ] else ...[
          'DTSTART:${_utc.format(e.startAt!.toUtc())}',
          'DTEND:${_utc.format(e.endAt!.toUtc())}',
        ],
        'SUMMARY:${_escape(i.title)}',
        if (i.location != null) 'LOCATION:${_escape(i.location!)}',
        'DESCRIPTION:${_escape(calendarNotes(i))}',
        'URL:${planLink(e)}',
        'END:VEVENT',
      ]);
    }
  }
  lines.add('END:VCALENDAR');
  return '${lines.map(_fold).join('\r\n')}\r\n';
}

/// RFC 5545 text escaping.
String _escape(String s) => s
    .replaceAll(r'\', r'\\')
    .replaceAll(';', r'\;')
    .replaceAll(',', r'\,')
    .replaceAll(RegExp(r'\r?\n'), r'\n');

/// Lines longer than 75 bytes continue on the next line after a space, without
/// splitting a character.
String _fold(String line) {
  if (utf8.encode(line).length <= 75) return line;
  final out = StringBuffer();
  var width = 0;
  for (final rune in line.runes) {
    final ch = String.fromCharCode(rune);
    final n = utf8.encode(ch).length;
    if (width + n > 75) {
      out.write('\r\n ');
      width = 1;
    }
    out.write(ch);
    width += n;
  }
  return out.toString();
}
