import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';

SupabaseClient get _db => Supabase.instance.client;
String get _me => _db.auth.currentUser!.id;

const avatarBucket = 'avatars';

/// A group the viewer shares with someone (or, on their own profile, any of theirs).
typedef SharedGroup = ({String groupId, String name, int members});

/// Counts shown on the user's own profile.
typedef ProfileStats = ({int groups, int activities, int upcomingPlans});

class ProfileRepository {
  Future<Profile> profile(String userId) async {
    final row = await _db
        .from('profiles')
        .select('${Profile.columns}, bio, timezone')
        .eq('id', userId)
        .single();
    return Profile.fromJson(row);
  }

  /// Saves the editable text fields. A taken username fails with 23505.
  Future<void> update({required String username, String? displayName, String? bio}) {
    String? blank(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();
    return _db.from('profiles').update({
      'username': username.trim().toLowerCase(),
      'display_name': blank(displayName),
      'bio': blank(bio),
    }).eq('id', _me);
  }

  Future<bool> usernameAvailable(String username) async =>
      await _db.rpc('username_available', params: {'p_username': username}) as bool;

  /// Uploads a new picture to `avatars/<user id>/`, points the profile at it and
  /// removes the previous file.
  Future<void> setAvatar(Uint8List bytes, {required String extension, String? previousPath}) async {
    final ext = extension.toLowerCase().replaceAll('.', '');
    final path = '$_me/${DateTime.now().microsecondsSinceEpoch}.$ext';
    await _db.storage.from(avatarBucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: ext == 'png' ? 'image/png' : 'image/jpeg'),
        );
    await _db.from('profiles').update({'avatar_path': path}).eq('id', _me);
    if (previousPath != null) await _db.storage.from(avatarBucket).remove([previousPath]);
  }

  Future<void> removeAvatar(String path) async {
    await _db.from('profiles').update({'avatar_path': null}).eq('id', _me);
    await _db.storage.from(avatarBucket).remove([path]);
  }

  Future<String> avatarUrl(String path) => _db.storage.from(avatarBucket).createSignedUrl(path, 60 * 60);

  Future<List<SharedGroup>> sharedGroups(String userId) async {
    final rows = await _db.rpc('shared_groups', params: {'p_user': userId}) as List;
    return [
      for (final r in rows.cast<Map<String, dynamic>>())
        (groupId: r['group_id'] as String, name: r['group_name'] as String, members: r['member_count'] as int),
    ];
  }

  Future<ProfileStats> myStats() async {
    final rows = await _db.rpc('my_profile_stats') as List;
    final r = rows.first as Map<String, dynamic>;
    return (groups: r['groups'] as int, activities: r['activities'] as int, upcomingPlans: r['upcoming_plans'] as int);
  }

  // ---- Account -------------------------------------------------------------

  /// Sends a confirmation link; the email changes once it's confirmed.
  Future<void> changeEmail(String email) => _db.auth.updateUser(UserAttributes(email: email.trim()));

  /// Checks the current password first, since Supabase doesn't ask for it.
  Future<void> changePassword({required String current, required String next}) async {
    final email = _db.auth.currentUser!.email!;
    await _db.auth.signInWithPassword(email: email, password: current);
    await _db.auth.updateUser(UserAttributes(password: next));
  }
}

final profileRepositoryProvider = Provider((_) => ProfileRepository());

final profileProvider =
    FutureProvider.family<Profile, String>((ref, id) => ref.watch(profileRepositoryProvider).profile(id));

final sharedGroupsProvider = FutureProvider.autoDispose.family<List<SharedGroup>, String>(
    (ref, id) => ref.watch(profileRepositoryProvider).sharedGroups(id));

final myStatsProvider =
    FutureProvider.autoDispose<ProfileStats>((ref) => ref.watch(profileRepositoryProvider).myStats());

final avatarUrlProvider =
    FutureProvider.family<String, String>((ref, path) => ref.watch(profileRepositoryProvider).avatarUrl(path));
