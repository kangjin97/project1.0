import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_clock.dart';
import 'models.dart';
import 'schedule_models.dart';

SupabaseClient get _db => Supabase.instance.client;
String get _me => _db.auth.currentUser!.id;

/// Which slice of the schedule to load.
typedef ScheduleQuery = ({DateTime from, DateTime to, String? groupId, bool includeUnscheduled});

/// A schedule window that contains one plan, so its detail sheet finds it.
/// Group view when [groupId] is given (also covers "no date yet" ideas).
/// [date] for all-day plans; [start]/[end] in the display zone for timed ones.
ScheduleQuery queryAroundEntry({String? groupId, DateTime? date, DateTime? start, DateTime? end}) {
  final from = date ?? start;
  if (from == null) {
    final today = AppClock.today();
    return (from: today, to: today, groupId: groupId, includeUnscheduled: true);
  }
  final to = date ?? end ?? from;
  return (from: dateOnly(from), to: dateOnly(to), groupId: groupId, includeUnscheduled: false);
}

class ScheduleRepository {
  /// Entries between two local dates (inclusive). Without [groupId], the
  /// user's own schedule; with it, the whole group's.
  Future<List<ScheduleEntry>> list(ScheduleQuery q) async {
    final rows = await _db.rpc('list_schedule', params: {
      'p_from': isoDate(q.from),
      'p_to': isoDate(q.to),
      'p_tz': AppClock.zoneName,
      'p_group': q.groupId,
      'p_include_unscheduled': q.includeUnscheduled,
    }) as List;
    return [for (final r in rows) ScheduleEntry.fromJson(r as Map<String, dynamic>)];
  }

  /// Creates an activity entry, or an event when [activityId] is null.
  /// Without [force], returns the clashes and saves nothing if anyone is busy.
  Future<ScheduleResult> create({
    required String groupId,
    String? activityId,
    String? title,
    required EntryTiming timing,
    required List<String> participantIds,
    bool force = false,
  }) async {
    final result = await _db.rpc('create_schedule_entry', params: {
      'p_group_id': groupId,
      'p_activity_id': activityId,
      'p_title': title,
      ..._timingParams(timing),
      'p_participant_ids': participantIds,
      'p_force': force,
    });
    return ScheduleResult.fromJson(result as Map<String, dynamic>);
  }

  /// Creates a repeating plan: one plan per date from [timing]'s date up to
  /// [until]. Every date is checked for clashes; nothing is saved without
  /// [force] if anyone is busy on any of them.
  Future<ScheduleResult> createSeries({
    required String groupId,
    String? activityId,
    String? title,
    required EntryTiming timing,
    required List<String> participantIds,
    required RepeatFreq freq,
    required DateTime until,
    bool force = false,
  }) async {
    final result = await _db.rpc('create_schedule_series', params: {
      'p_group_id': groupId,
      'p_activity_id': activityId,
      'p_title': title,
      ..._timingParams(timing),
      'p_participant_ids': participantIds,
      'p_freq': freq.db,
      'p_until': isoDate(until),
      'p_force': force,
    });
    return ScheduleResult.fromJson(result as Map<String, dynamic>);
  }

  /// Adds dates after a series' last one, up to [until] (copying the last plan).
  Future<ScheduleResult> extendSeries(String entryId, DateTime until, {bool force = false}) async {
    final result = await _db.rpc('extend_series',
        params: {'p_entry': entryId, 'p_until': isoDate(until), 'p_force': force});
    return ScheduleResult.fromJson(result as Map<String, dynamic>);
  }

  /// Moves an entry; re-checks every participant for clashes.
  /// [scope] following also shifts the series' later dates by the same amount.
  Future<ScheduleResult> reschedule(String entryId, EntryTiming timing,
      {bool force = false, EditScope scope = EditScope.one}) async {
    final result = await _db.rpc(scope == EditScope.following ? 'reschedule_following' : 'reschedule_entry', params: {
      'p_entry': entryId,
      ..._timingParams(timing),
      'p_force': force,
    });
    return ScheduleResult.fromJson(result as Map<String, dynamic>);
  }

  /// Adds group members to an entry; checks only the new people for clashes.
  Future<ScheduleResult> addParticipants(String entryId, List<String> userIds,
      {bool force = false, EditScope scope = EditScope.one}) async {
    final result = await _db.rpc(scope == EditScope.following ? 'add_participants_following' : 'add_entry_participants', params: {
      'p_entry': entryId,
      'p_user_ids': userIds,
      'p_force': force,
    });
    return ScheduleResult.fromJson(result as Map<String, dynamic>);
  }

  /// Puts an activity on the entry: replaces an event, or swaps the activity.
  /// [scope] following applies the change to the series' later dates too.
  Future<void> setActivity(String entryId, String activityId, {EditScope scope = EditScope.one}) =>
      scope == EditScope.following
          ? _db.rpc('set_activity_following', params: {'p_entry': entryId, 'p_activity_id': activityId})
          : _db.from('schedule_entries').update({'activity_id': activityId}).eq('id', entryId);

  Future<void> rename(String entryId, String title, {EditScope scope = EditScope.one}) =>
      scope == EditScope.following
          ? _db.rpc('rename_following', params: {'p_entry': entryId, 'p_title': title.trim()})
          : _db.from('schedule_entries').update({'title': title.trim()}).eq('id', entryId);

  /// Removes the entry from the group schedule (and everyone's schedule).
  Future<void> delete(String entryId, {EditScope scope = EditScope.one}) => scope == EditScope.following
      ? _db.rpc('delete_following', params: {'p_entry': entryId})
      : _db.from('schedule_entries').delete().eq('id', entryId);

  /// Takes the current user off the entry.
  Future<void> leave(String entryId, {EditScope scope = EditScope.one}) => scope == EditScope.following
      ? _db.rpc('leave_following', params: {'p_entry': entryId})
      : _db.from('schedule_participants').delete().eq('entry_id', entryId).eq('user_id', _me);

  /// The current user keeps the entry despite an overlap.
  Future<void> acknowledgeClash(String entryId) => _db
      .from('schedule_participants')
      .update({'status': 'added'})
      .eq('entry_id', entryId)
      .eq('user_id', _me);

  /// Who changed what on this entry, newest first.
  Future<List<ChangeEntry>> history(String entryId) async {
    final rows = await _db
        .from('change_log')
        .select('entity_type, action, actor_id, before, after, created_at')
        .eq('entity_id', entryId)
        .inFilter('entity_type', ['schedule_entry', 'schedule_participant'])
        .order('created_at', ascending: false)
        .limit(50);
    final actorIds = {for (final r in rows) r['actor_id'] as String?}.whereType<String>().toList();
    final names = <String, String>{};
    if (actorIds.isNotEmpty) {
      final profiles = await _db.from('profiles').select('id, username').inFilter('id', actorIds);
      for (final p in profiles) {
        names[p['id'] as String] = p['username'] as String;
      }
    }
    return [
      for (final r in rows)
        ChangeEntry(
          entityType: r['entity_type'] as String,
          action: r['action'] as String,
          actorUsername: names[r['actor_id']],
          createdAt: DateTime.parse(r['created_at'] as String),
          before: r['before'] as Map<String, dynamic>?,
          after: r['after'] as Map<String, dynamic>?,
        ),
    ];
  }

  Map<String, dynamic> _timingParams(EntryTiming timing) => switch (timing) {
        AllDayTiming(:final date) => {
            'p_all_day': true,
            'p_date': isoDate(date),
            'p_start_at': null,
            'p_end_at': null,
          },
        TimedTiming(:final start, :final end) => {
            'p_all_day': false,
            'p_date': null,
            'p_start_at': start.toUtc().toIso8601String(),
            'p_end_at': end.toUtc().toIso8601String(),
          },
        UnscheduledTiming() => {'p_all_day': false, 'p_date': null, 'p_start_at': null, 'p_end_at': null},
      };
}

final scheduleRepositoryProvider = Provider((_) => ScheduleRepository());

final scheduleProvider = FutureProvider.autoDispose.family<List<ScheduleEntry>, ScheduleQuery>((ref, q) {
  // Refetch in the new zone when the user changes it.
  ref.watch(timezoneProvider);
  return ref.watch(scheduleRepositoryProvider).list(q);
});

final entryHistoryProvider = FutureProvider.autoDispose.family<List<ChangeEntry>, String>(
    (ref, id) => ref.watch(scheduleRepositoryProvider).history(id));

/// Refreshes every schedule view after a change.
void invalidateSchedule(WidgetRef ref) {
  ref.invalidate(scheduleProvider);
  ref.invalidate(entryHistoryProvider);
}
