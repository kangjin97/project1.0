import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'groups_repository.dart';
import 'models.dart';

SupabaseClient get _db => Supabase.instance.client;
String get _me => _db.auth.currentUser!.id;

const photoBucket = 'activity-photos';

/// The editable fields of an activity.
class ActivityInput {
  ActivityInput({
    required this.name,
    this.description,
    this.location,
    this.placeId,
    this.priceMin,
    this.priceMax,
    this.currency = 'SGD',
    this.url,
    this.personalTypeId,
    this.setLabel = false,
  });

  final String name;
  final String? description;
  final String? location;

  /// The Google place picked for [location]; null for free text.
  final String? placeId;
  final double? priceMin;
  final double? priceMax;
  final String currency;
  final String? url;

  /// The owner's label. Only sent when [setLabel] is true (owners only).
  final String? personalTypeId;
  final bool setLabel;

  Map<String, dynamic> toJson() {
    String? blank(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();
    return {
      'name': name.trim(),
      'description': blank(description),
      'location': blank(location),
      // A place only goes with location text (the database also drops it when
      // the text changes without a new pick).
      'place_id': blank(location) == null ? null : placeId,
      'price_min': priceMin,
      'price_max': priceMax,
      'currency': currency.trim().toUpperCase(),
      'url': blank(url),
      if (setLabel) 'personal_type_id': personalTypeId,
    };
  }
}

class ActivitiesRepository {
  // ---- Activities ----------------------------------------------------------

  Future<List<Activity>> myActivities() async {
    final rows = await _db
        .from('activities')
        .select('${Activity.columns}, group_activities(group_id)')
        .eq('owner_id', _me)
        .isFilter('deleted_at', null)
        .order('created_at', ascending: false);
    return rows.map(Activity.fromJson).toList();
  }

  /// Any activity the user can see: their own, or one shared into their groups.
  Future<Activity?> activity(String id) async {
    final row = await _db.from('activities').select(Activity.columns).eq('id', id).maybeSingle();
    return row == null ? null : Activity.fromJson(row);
  }

  Future<String> create(ActivityInput input) async {
    final row = await _db.from('activities').insert(input.toJson()).select('id').single();
    return row['id'] as String;
  }

  /// Creates many at once (#111, spreadsheet import), 100 per request.
  /// Returns how many were created.
  Future<int> createMany(List<ActivityInput> inputs) async {
    var created = 0;
    for (var i = 0; i < inputs.length; i += 100) {
      final rows = await _db
          .from('activities')
          .insert([for (final input in inputs.sublist(i, min(i + 100, inputs.length))) input.toJson()])
          .select('id');
      created += rows.length;
    }
    return created;
  }

  Future<void> update(String id, ActivityInput input) =>
      _db.from('activities').update(input.toJson()).eq('id', id);

  /// Owner only. Schedule entries using it turn back into events.
  Future<void> delete(String id) => _db.rpc('delete_activity', params: {'p_activity': id});

  // ---- Groups --------------------------------------------------------------

  Future<List<GroupActivity>> groupActivities(String groupId) async {
    final rows = await _db
        .from('group_activities')
        .select(GroupActivity.columns)
        .eq('group_id', groupId)
        .order('added_at', ascending: false);
    return rows.map(GroupActivity.fromJson).toList();
  }

  /// The user's groups this activity is shared into, with the type in each.
  Future<List<({String groupId, String groupName, String typeId, String? typeName})>> sharedIn(
      String activityId) async {
    final rows = await _db
        .from('group_activities')
        .select('group_id, type_id, groups(name), activity_types(name)')
        .eq('activity_id', activityId);
    return [
      for (final r in rows)
        (
          groupId: r['group_id'] as String,
          groupName: (r['groups'] as Map?)?['name'] as String? ?? 'Group',
          typeId: r['type_id'] as String,
          typeName: (r['activity_types'] as Map?)?['name'] as String?,
        ),
    ];
  }

  /// Leave [typeId] null to file it by the owner's label.
  Future<void> share({required String activityId, required String groupId, String? typeId}) =>
      _db.from('group_activities').insert({
        'group_id': groupId,
        'activity_id': activityId,
        'type_id': ?typeId,
      });

  /// Where an activity labelled [label] would be filed in [groupId].
  Future<TypePreview> previewType(String groupId, String label) async {
    final rows = await _db.rpc('preview_group_type', params: {'p_group': groupId, 'p_name': label}) as List;
    return TypePreview.fromJson(rows.first as Map<String, dynamic>);
  }

  // ---- Personal labels -----------------------------------------------------

  Future<List<PersonalType>> labels() async {
    final rows = await _db.from('personal_types').select('id, name');
    return rows.map(PersonalType.fromJson).toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  Future<String> addLabel(String name) async {
    final row = await _db.from('personal_types').insert({'name': name.trim()}).select('id').single();
    return row['id'] as String;
  }

  /// Label ids for [names] (ignoring case and spaces), creating the ones the
  /// user doesn't have yet. Keyed by the lower-cased, trimmed name.
  Future<Map<String, String>> labelIdsFor(Iterable<String> names) async {
    final ids = {for (final l in await labels()) l.name.trim().toLowerCase(): l.id};
    for (final name in names.map((n) => n.trim()).where((n) => n.isNotEmpty)) {
      final key = name.toLowerCase();
      if (!ids.containsKey(key)) ids[key] = await addLabel(name);
    }
    return ids;
  }

  /// Renaming re-files every activity with this label in its groups.
  Future<void> renameLabel(String id, String name) =>
      _db.from('personal_types').update({'name': name.trim()}).eq('id', id);

  /// Activities keep their current group types.
  Future<void> deleteLabel(String id) => _db.from('personal_types').delete().eq('id', id);

  // ---- Copies (#112) ------------------------------------------------------

  /// Saves a private copy of someone else's [source] into my activities and
  /// copies its photo files into the copy's own folder. The label comes from
  /// the activity's type in [groupId] (or the group it was shared into first).
  /// Returns the copy's id and how many photos couldn't be copied; the copy is
  /// kept either way.
  Future<({String id, int photosMissed})> saveCopy(Activity source, {String? groupId}) async {
    final id = await _db.rpc(
          'copy_activity',
          params: {'p_activity': source.id, 'p_group': ?groupId},
        )
        as String;
    var missed = 0;
    for (final photo in source.photos) {
      try {
        final name = photo.storagePath.split('/').last;
        final path = '$id/$name';
        await _db.storage.from(photoBucket).copy(photo.storagePath, path);
        await _db.from('activity_photos').insert({'activity_id': id, 'storage_path': path, 'position': photo.position});
      } catch (_) {
        missed++;
      }
    }
    return (id: id, photosMissed: missed);
  }

  /// My live copy of [activityId], if I've saved one.
  Future<String?> myCopyOf(String activityId) async {
    final row = await _db
        .from('activities')
        .select('id')
        .eq('owner_id', _db.auth.currentUser!.id)
        .eq('copied_from', activityId)
        .isFilter('deleted_at', null)
        .maybeSingle();
    return row?['id'] as String?;
  }

  /// Removes it from the group only; the activity itself is kept.
  Future<void> unshare({required String activityId, required String groupId}) =>
      _db.from('group_activities').delete().eq('group_id', groupId).eq('activity_id', activityId);

  Future<void> changeType({required String activityId, required String groupId, required String typeId}) =>
      _db.from('group_activities').update({'type_id': typeId}).eq('group_id', groupId).eq('activity_id', activityId);

  // ---- Photos --------------------------------------------------------------

  Future<void> addPhoto(String activityId, Uint8List bytes, {required String extension, int position = 0}) async {
    final ext = extension.toLowerCase().replaceAll('.', '');
    final name = '${DateTime.now().microsecondsSinceEpoch}${Random().nextInt(1 << 30)}';
    final path = '$activityId/$name.$ext';
    await _db.storage.from(photoBucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: ext == 'png' ? 'image/png' : 'image/jpeg'),
        );
    await _db.from('activity_photos').insert({'activity_id': activityId, 'storage_path': path, 'position': position});
  }

  Future<void> removePhoto(ActivityPhoto photo) async {
    await _db.from('activity_photos').delete().eq('id', photo.id);
    await _db.storage.from(photoBucket).remove([photo.storagePath]);
  }

  Future<String> photoUrl(String storagePath) =>
      _db.storage.from(photoBucket).createSignedUrl(storagePath, 60 * 60);

  // ---- History -------------------------------------------------------------

  Future<List<ChangeEntry>> history(String activityId) async {
    final rows = await _db
        .from('change_log')
        .select('entity_type, action, actor_id, before, after, created_at')
        .eq('entity_id', activityId)
        .inFilter('entity_type', ['activity', 'activity_photo', 'group_activity'])
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
}

final activitiesRepositoryProvider = Provider((_) => ActivitiesRepository());

final myActivitiesProvider =
    FutureProvider<List<Activity>>((ref) => ref.watch(activitiesRepositoryProvider).myActivities());

final activityProvider =
    FutureProvider.family<Activity?, String>((ref, id) => ref.watch(activitiesRepositoryProvider).activity(id));

final groupActivitiesProvider = FutureProvider.family<List<GroupActivity>, String>(
    (ref, groupId) => ref.watch(activitiesRepositoryProvider).groupActivities(groupId));

/// The id of my copy of an activity (#112), or null.
final myCopyProvider =
    FutureProvider.family<String?, String>((ref, id) => ref.watch(activitiesRepositoryProvider).myCopyOf(id));

final sharedInProvider = FutureProvider.family(
    (ref, String activityId) => ref.watch(activitiesRepositoryProvider).sharedIn(activityId));

final labelsProvider = FutureProvider<List<PersonalType>>((ref) => ref.watch(activitiesRepositoryProvider).labels());

final typePreviewProvider = FutureProvider.autoDispose.family<TypePreview, (String, String)>(
    (ref, key) => ref.watch(activitiesRepositoryProvider).previewType(key.$1, key.$2));

final activityHistoryProvider = FutureProvider.family<List<ChangeEntry>, String>(
    (ref, id) => ref.watch(activitiesRepositoryProvider).history(id));

final photoUrlProvider =
    FutureProvider.family<String, String>((ref, path) => ref.watch(activitiesRepositoryProvider).photoUrl(path));

/// Refreshes every view that might show this activity after a change.
void invalidateActivity(WidgetRef ref, String activityId, {String? groupId}) {
  ref.invalidate(myActivitiesProvider);
  ref.invalidate(activityProvider(activityId));
  ref.invalidate(sharedInProvider(activityId));
  ref.invalidate(activityHistoryProvider(activityId));
  if (groupId != null) {
    ref.invalidate(groupActivitiesProvider(groupId));
  } else {
    ref.invalidate(groupActivitiesProvider);
  }
}

/// After a label change, groups may have new types and re-filed activities.
void invalidateLabels(WidgetRef ref) {
  ref.invalidate(labelsProvider);
  ref.invalidate(myActivitiesProvider);
  ref.invalidate(activityProvider);
  ref.invalidate(sharedInProvider);
  ref.invalidate(groupActivitiesProvider);
  ref.invalidate(typesProvider);
}
