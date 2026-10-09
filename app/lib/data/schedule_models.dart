/// Someone taking part in a schedule entry.
class ScheduleParticipant {
  ScheduleParticipant({required this.userId, required this.username, this.displayName, required this.status});

  factory ScheduleParticipant.fromJson(Map<String, dynamic> j) => ScheduleParticipant(
        userId: j['user_id'] as String,
        username: j['username'] as String,
        displayName: j['display_name'] as String?,
        status: j['status'] as String,
      );

  final String userId;
  final String username;
  final String? displayName;

  /// 'added', or 'clash' until they acknowledge an overlap.
  final String status;

  String get label => (displayName?.isNotEmpty ?? false) ? displayName! : username;
  bool get hasClash => status == 'clash';
}

/// A plan on the schedule: an activity, or an event (placeholder) when [activityId] is null.
class ScheduleEntry {
  ScheduleEntry({
    required this.id,
    required this.groupId,
    required this.groupName,
    this.activityId,
    this.activityName,
    this.title,
    required this.allDay,
    this.date,
    this.startAt,
    this.endAt,
    required this.createdBy,
    this.myStatus,
    this.participants = const [],
  });

  /// From the `list_schedule` RPC.
  factory ScheduleEntry.fromJson(Map<String, dynamic> j) => ScheduleEntry(
        id: j['id'] as String,
        groupId: j['group_id'] as String,
        groupName: j['group_name'] as String,
        activityId: j['activity_id'] as String?,
        activityName: j['activity_name'] as String?,
        title: j['title'] as String?,
        allDay: j['all_day'] as bool,
        date: j['date'] == null ? null : DateTime.parse(j['date'] as String),
        startAt: j['start_at'] == null ? null : DateTime.parse(j['start_at'] as String).toLocal(),
        endAt: j['end_at'] == null ? null : DateTime.parse(j['end_at'] as String).toLocal(),
        createdBy: j['created_by'] as String,
        myStatus: j['my_status'] as String?,
        participants: [
          for (final p in (j['participants'] as List? ?? const []))
            ScheduleParticipant.fromJson(p as Map<String, dynamic>),
        ],
      );

  final String id;
  final String groupId;
  final String groupName;
  final String? activityId;
  final String? activityName;

  /// The event name; kept for history when an activity replaces the event.
  final String? title;
  final bool allDay;

  /// Set for all-day entries (a local calendar date).
  final DateTime? date;

  /// Set for timed entries, in local time.
  final DateTime? startAt;
  final DateTime? endAt;
  final String createdBy;

  /// The current user's participation, or null if they're not in it.
  final String? myStatus;
  final List<ScheduleParticipant> participants;

  bool get isEvent => activityId == null;
  bool get isUnscheduled => !allDay && startAt == null;
  bool get iAmIn => myStatus != null;
  bool get iHaveClash => myStatus == 'clash';
  String get displayTitle => activityName ?? title ?? 'Untitled';

  /// Local calendar days this entry occupies (several for multi-day timed entries).
  List<DateTime> get days {
    if (allDay && date != null) return [dateOnly(date!)];
    if (startAt == null || endAt == null) return const [];
    final first = dateOnly(startAt!);
    // An entry ending exactly at midnight doesn't occupy the next day.
    final last = dateOnly(endAt!.subtract(const Duration(microseconds: 1)));
    return [for (var d = first; !d.isAfter(last); d = addDays(d, 1)) d];
  }

  bool occursOn(DateTime day) => days.any((d) => isSameDay(d, day));
}

/// An existing entry that overlaps the proposed time for one person.
class ScheduleClash {
  ScheduleClash({
    required this.userId,
    required this.username,
    required this.title,
    required this.allDay,
    this.date,
    this.startAt,
    this.endAt,
  });

  factory ScheduleClash.fromJson(Map<String, dynamic> j) => ScheduleClash(
        userId: j['user_id'] as String,
        username: j['username'] as String,
        title: j['title'] as String? ?? 'Busy',
        allDay: j['all_day'] as bool,
        date: j['entry_date'] == null ? null : DateTime.parse(j['entry_date'] as String),
        startAt: j['start_at'] == null ? null : DateTime.parse(j['start_at'] as String).toLocal(),
        endAt: j['end_at'] == null ? null : DateTime.parse(j['end_at'] as String).toLocal(),
      );

  final String userId;
  final String username;

  /// "Busy" when the clashing entry is in a group the planner isn't in.
  final String title;
  final bool allDay;
  final DateTime? date;
  final DateTime? startAt;
  final DateTime? endAt;
}

/// Outcome of creating/rescheduling an entry or adding people to it.
class ScheduleResult {
  ScheduleResult({required this.saved, this.entryId, this.clashes = const []});

  factory ScheduleResult.fromJson(Map<String, dynamic> j) => ScheduleResult(
        saved: j['status'] != 'clash',
        entryId: j['entry_id'] as String?,
        clashes: [
          for (final c in (j['clashes'] as List? ?? const [])) ScheduleClash.fromJson(c as Map<String, dynamic>),
        ],
      );

  /// False when nothing was saved because of clashes (retry with force).
  final bool saved;
  final String? entryId;
  final List<ScheduleClash> clashes;
}

/// When an entry happens. Exactly one shape applies.
sealed class EntryTiming {
  const EntryTiming();
}

class AllDayTiming extends EntryTiming {
  const AllDayTiming(this.date);
  final DateTime date;
}

class TimedTiming extends EntryTiming {
  const TimedTiming(this.start, this.end);
  final DateTime start;
  final DateTime end;
}

/// Events only: no date yet.
class UnscheduledTiming extends EntryTiming {
  const UnscheduledTiming();
}

// ---- Date helpers -------------------------------------------------------------

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Calendar-day arithmetic that stays at midnight across DST changes.
DateTime addDays(DateTime d, int days) => DateTime(d.year, d.month, d.day + days);

bool isSameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// Monday of the week containing [d].
DateTime startOfWeek(DateTime d) => addDays(dateOnly(d), -(d.weekday - DateTime.monday));

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
