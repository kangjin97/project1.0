import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';

SupabaseClient get _db => Supabase.instance.client;
String get _me => _db.auth.currentUser!.id;

class ActivitiesRepository {
  Future<List<Activity>> fetchMyActivities() async {
    final rows = await _db
        .from('activities')
        .select('id, owner_id, name, description, created_at')
        .eq('owner_id', _me)
        .isFilter('deleted_at', null)
        .order('created_at', ascending: false);
    return rows.map(Activity.fromJson).toList();
  }

  Future<void> createActivity({
    required String name,
    String? description,
    String? defaultActivityTypeId,
  }) async {
    await _db.from('activities').insert({
      'name': name.trim(),
      if (description?.trim().isNotEmpty ?? false) 'description': description!.trim(),
    });
  }

  Future<void> updateActivity({
    required String id,
    required String name,
    String? description,
    String? defaultActivityTypeId,
  }) async {
    await _db.from('activities').update({
      'name': name.trim(),
      'description': description?.trim().isNotEmpty == true ? description!.trim() : null,
    }).eq('id', id);
  }

  Future<void> deleteActivity(String id) async {
    await _db.rpc('delete_activity', params: {'p_activity': id});
  }

  Future<List<GroupActivity>> fetchGroupActivities(String groupId) async {
    final rows = await _db
        .from('group_activities')
        .select(
          'group_id, activity_id, type_id, added_by, added_at, '
          'activities(id, owner_id, name, description, created_at), '
          'activity_types(name), '
          'sharer:profiles!group_activities_added_by_fkey(username)',
        )
        .eq('group_id', groupId)
        .order('added_at');
    return rows.map(GroupActivity.fromJson).toList();
  }

  Future<void> shareActivityToGroup({
    required String activityId,
    required String groupId,
    required String activityTypeId,
  }) async {
    await _db.from('group_activities').insert({
      'group_id': groupId,
      'activity_id': activityId,
      'type_id': activityTypeId,
    });
  }

  Future<void> unshareActivityFromGroup({
    required String groupId,
    required String activityId,
  }) async {
    await _db
        .from('group_activities')
        .delete()
        .eq('group_id', groupId)
        .eq('activity_id', activityId);
  }
}

final activitiesRepositoryProvider = Provider((_) => ActivitiesRepository());

final myActivitiesProvider = FutureProvider<List<Activity>>(
  (ref) => ref.watch(activitiesRepositoryProvider).fetchMyActivities(),
);

final groupActivitiesProvider = FutureProvider.family<List<GroupActivity>, String>(
  (ref, groupId) => ref.watch(activitiesRepositoryProvider).fetchGroupActivities(groupId),
);
