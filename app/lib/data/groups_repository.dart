import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';

SupabaseClient get _db => Supabase.instance.client;
String get _me => _db.auth.currentUser!.id;

class GroupsRepository {
  Future<List<Group>> myGroups() async {
    final memberships = await _db.from('group_members').select('group_id').eq('user_id', _me);
    final ids = [for (final m in memberships) m['group_id'] as String];
    if (ids.isEmpty) return [];
    final rows = await _db
        .from('groups')
        .select('id, name, group_members(count)')
        .inFilter('id', ids)
        .order('created_at', ascending: true);
    return rows.map(Group.fromJson).toList();
  }

  Future<Group> group(String id) async {
    final row = await _db.from('groups').select('id, name, group_members(count)').eq('id', id).single();
    return Group.fromJson(row);
  }

  Future<String> createGroup(String name) async {
    final row = await _db.from('groups').insert({'name': name.trim()}).select('id').single();
    return row['id'] as String;
  }

  Future<void> renameGroup(String id, String name) =>
      _db.from('groups').update({'name': name.trim()}).eq('id', id);

  Future<void> leaveGroup(String id) =>
      _db.from('group_members').delete().eq('group_id', id).eq('user_id', _me);

  Future<List<Member>> members(String groupId) async {
    final rows = await _db
        .from('group_members')
        .select('role, profiles(id, username, display_name)')
        .eq('group_id', groupId)
        .order('joined_at', ascending: true);
    return rows.map(Member.fromJson).toList();
  }

  Future<void> removeMember(String groupId, String userId) =>
      _db.from('group_members').delete().eq('group_id', groupId).eq('user_id', userId);

  // ---- Invites -------------------------------------------------------------

  /// Finds users by username prefix, or by exact email when the query has an @.
  Future<List<Profile>> searchUsers(String query) async {
    final q = query.trim();
    if (q.length < 2) return [];
    if (q.contains('@')) {
      final rows = await _db.rpc('find_user_by_email', params: {'p_email': q}) as List;
      return rows.map((r) => Profile.fromJson(r as Map<String, dynamic>)).toList();
    }
    final rows = await _db
        .from('profiles')
        .select('id, username, display_name')
        // Usernames are [a-z0-9_]; escape _ so it matches literally. PostgREST uses * as the wildcard.
        .ilike('username', '${q.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '').replaceAll('_', r'\_')}*')
        .neq('id', _me)
        .limit(10);
    return rows.map(Profile.fromJson).toList();
  }

  Future<void> invite(String groupId, String userId) =>
      _db.from('group_invitations').insert({'group_id': groupId, 'invitee_id': userId});

  Future<String> createInviteLink(String groupId, {Duration validFor = const Duration(days: 7)}) async {
    final row = await _db
        .from('group_invite_links')
        .insert({
          'group_id': groupId,
          'expires_at': DateTime.now().toUtc().add(validFor).toIso8601String(),
        })
        .select('token')
        .single();
    return row['token'] as String;
  }

  Future<List<Invitation>> pendingInvitations() async {
    final rows = await _db
        .from('group_invitations')
        .select('id, groups(name), inviter:profiles!group_invitations_invited_by_fkey(username)')
        .eq('invitee_id', _me)
        .eq('status', 'pending')
        .order('created_at', ascending: true);
    return rows.map(Invitation.fromJson).toList();
  }

  Future<void> respond(String invitationId, {required bool accept}) =>
      _db.rpc('respond_to_invitation', params: {'p_invitation': invitationId, 'p_accept': accept});

  Future<({String groupId, String name, int members})?> previewLink(String token) async {
    final rows = await _db.rpc('preview_invite_link', params: {'p_token': token}) as List;
    if (rows.isEmpty) return null;
    final r = rows.first as Map<String, dynamic>;
    return (groupId: r['group_id'] as String, name: r['group_name'] as String, members: r['member_count'] as int);
  }

  Future<String> joinViaLink(String token) async =>
      await _db.rpc('join_group_via_link', params: {'p_token': token}) as String;

  // ---- Activity types ------------------------------------------------------

  Future<List<ActivityType>> types(String groupId) async {
    final rows = await _db.from('activity_types').select('id, name').eq('group_id', groupId);
    return rows.map(ActivityType.fromJson).toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  Future<void> addType(String groupId, String name) =>
      _db.from('activity_types').insert({'group_id': groupId, 'name': name.trim()});

  Future<void> renameType(String id, String name) =>
      _db.from('activity_types').update({'name': name.trim()}).eq('id', id);

  Future<void> deleteType(String id) => _db.from('activity_types').delete().eq('id', id);

  // ---- Type merging --------------------------------------------------------

  Future<List<TypeMerge>> merges(String groupId) async {
    final rows = await _db
        .from('type_merges')
        .select('id, source_name, target_type_id')
        .eq('group_id', groupId)
        .order('source_name', ascending: true);
    return rows.map(TypeMerge.fromJson).toList();
  }

  /// Merges [sourceTypeIds] into [targetTypeId], or into a type named [targetName].
  Future<void> mergeTypes(String groupId, List<String> sourceTypeIds, {String? targetTypeId, String? targetName}) =>
      _db.rpc('merge_types', params: {
        'p_group': groupId,
        'p_source_type_ids': sourceTypeIds,
        'p_target_type_id': targetTypeId,
        'p_target_name': targetName,
      });

  /// Activities that came in with that label return to a type of that name.
  Future<void> removeMerge(String mergeId) => _db.rpc('remove_type_merge', params: {'p_merge': mergeId});
}

final groupsRepositoryProvider = Provider((_) => GroupsRepository());

final myGroupsProvider = FutureProvider<List<Group>>((ref) => ref.watch(groupsRepositoryProvider).myGroups());

final invitationsProvider =
    FutureProvider<List<Invitation>>((ref) => ref.watch(groupsRepositoryProvider).pendingInvitations());

final groupProvider =
    FutureProvider.family<Group, String>((ref, id) => ref.watch(groupsRepositoryProvider).group(id));

final membersProvider =
    FutureProvider.family<List<Member>, String>((ref, id) => ref.watch(groupsRepositoryProvider).members(id));

final mergesProvider =
    FutureProvider.family<List<TypeMerge>, String>((ref, id) => ref.watch(groupsRepositoryProvider).merges(id));

final typesProvider =
    FutureProvider.family<List<ActivityType>, String>((ref, id) => ref.watch(groupsRepositoryProvider).types(id));

/// Turns database errors into something a person can act on.
String friendlyError(Object e) {
  if (e is PostgrestException) {
    if (e.code == '23505') return 'That already exists.';
    if (e.code == '23503') return 'It’s still in use, so it can’t be removed yet.';
    if (e.code == '42501') return 'You don’t have permission to do that.';
    return e.message;
  }
  if (e is AuthException) return e.message;
  return 'Something went wrong. Please try again.';
}
