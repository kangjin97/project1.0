import 'app_clock.dart';

class Profile {
  Profile({required this.id, required this.username, this.displayName, this.avatarPath, this.bio, this.timezone});

  /// Columns for showing a person in lists.
  static const columns = 'id, username, display_name, avatar_path';

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        id: j['id'] as String,
        username: j['username'] as String,
        displayName: j['display_name'] as String?,
        avatarPath: j['avatar_path'] as String?,
        bio: j['bio'] as String?,
        timezone: j['timezone'] as String?,
      );

  final String id;
  final String username;
  final String? displayName;

  /// Path in the `avatars` bucket, or null for the initial-letter avatar.
  final String? avatarPath;
  final String? bio;
  final String? timezone;

  String get label => (displayName?.isNotEmpty ?? false) ? displayName! : username;
}

class Group {
  Group({required this.id, required this.name, required this.memberCount});

  factory Group.fromJson(Map<String, dynamic> j) => Group(
        id: j['id'] as String,
        name: j['name'] as String,
        memberCount: (j['group_members'] as List?)?.isNotEmpty == true
            ? (j['group_members'][0]['count'] as int)
            : 0,
      );

  final String id;
  final String name;
  final int memberCount;
}

class Member {
  Member({required this.profile, required this.role});

  factory Member.fromJson(Map<String, dynamic> j) => Member(
        profile: Profile.fromJson(j['profiles'] as Map<String, dynamic>),
        role: j['role'] as String,
      );

  final Profile profile;
  final String role;

  bool get isOwner => role == 'owner';
}

class ActivityType {
  ActivityType({required this.id, required this.name});

  factory ActivityType.fromJson(Map<String, dynamic> j) =>
      ActivityType(id: j['id'] as String, name: j['name'] as String);

  final String id;
  final String name;
}

class Invitation {
  Invitation({required this.id, required this.groupName, required this.invitedBy});

  factory Invitation.fromJson(Map<String, dynamic> j) => Invitation(
        id: j['id'] as String,
        groupName: (j['groups'] as Map?)?['name'] as String? ?? 'A group',
        invitedBy: (j['inviter'] as Map?)?['username'] as String? ?? 'a deleted user',
      );

  final String id;
  final String groupName;
  final String invitedBy;
}

/// An invite link of a group, as listed on the Members tab.
class InviteLink {
  InviteLink({
    required this.id,
    required this.token,
    required this.createdByUsername,
    required this.createdAt,
    this.expiresAt,
    this.maxUses,
    required this.useCount,
  });

  factory InviteLink.fromJson(Map<String, dynamic> j) => InviteLink(
        id: j['id'] as String,
        token: j['token'] as String,
        createdByUsername: (j['creator'] as Map?)?['username'] as String?,
        createdAt: DateTime.parse(j['created_at'] as String),
        expiresAt: j['expires_at'] == null ? null : DateTime.parse(j['expires_at'] as String),
        maxUses: j['max_uses'] as int?,
        useCount: j['use_count'] as int,
      );

  static const columns =
      'id, token, created_at, expires_at, max_uses, use_count, creator:profiles!group_invite_links_created_by_fkey(username)';

  final String id;
  final String token;

  /// Null when the creator deleted their account.
  final String? createdByUsername;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final int? maxUses;
  final int useCount;

  /// Whether it still lets people join at [now]: not expired or used up.
  /// (Revoked links aren't loaded.)
  bool isActiveAt(DateTime now) =>
      (expiresAt == null || expiresAt!.isAfter(now)) && (maxUses == null || useCount < maxUses!);
}

/// A pending invitation sent from a group, as listed on the Members tab.
class SentInvitation {
  SentInvitation({required this.id, required this.invitee, required this.invitedByUsername, required this.createdAt});

  factory SentInvitation.fromJson(Map<String, dynamic> j) => SentInvitation(
        id: j['id'] as String,
        invitee: Profile.fromJson(j['invitee'] as Map<String, dynamic>),
        invitedByUsername: (j['inviter'] as Map?)?['username'] as String?,
        createdAt: DateTime.parse(j['created_at'] as String),
      );

  static const columns = 'id, created_at, invitee:profiles!group_invitations_invitee_id_fkey(${Profile.columns}), '
      'inviter:profiles!group_invitations_invited_by_fkey(username)';

  final String id;
  final Profile invitee;

  /// Null when the inviter deleted their account.
  final String? invitedByUsername;
  final DateTime createdAt;
}

class Activity {
  Activity({
    required this.id,
    required this.ownerId,
    required this.name,
    this.description,
    this.location,
    this.priceMin,
    this.priceMax,
    this.currency = 'SGD',
    this.url,
    required this.createdAt,
    required this.updatedAt,
    this.photos = const [],
    this.sharedGroupCount,
    this.personalTypeId,
    this.personalTypeName,
  });

  /// Columns to select for an activity, including its photos.
  static const columns = 'id, owner_id, name, description, location, price_min, price_max, currency, url, '
      'created_at, updated_at, personal_type_id, activity_photos(id, storage_path, position), '
      'personal_type:personal_types!activities_personal_type_fk(name)';

  factory Activity.fromJson(Map<String, dynamic> j) => Activity(
        id: j['id'] as String,
        ownerId: j['owner_id'] as String,
        name: j['name'] as String,
        description: j['description'] as String?,
        location: j['location'] as String?,
        priceMin: (j['price_min'] as num?)?.toDouble(),
        priceMax: (j['price_max'] as num?)?.toDouble(),
        currency: (j['currency'] as String?)?.trim() ?? 'SGD',
        url: j['url'] as String?,
        createdAt: DateTime.parse(j['created_at'] as String),
        updatedAt: DateTime.parse(j['updated_at'] as String),
        photos: [
          for (final p in (j['activity_photos'] as List? ?? const []))
            ActivityPhoto.fromJson(p as Map<String, dynamic>),
        ]..sort((a, b) => a.position.compareTo(b.position)),
        sharedGroupCount: (j['group_activities'] as List?)?.length,
        personalTypeId: j['personal_type_id'] as String?,
        personalTypeName: (j['personal_type'] as Map?)?['name'] as String?,
      );

  final String id;
  final String ownerId;
  final String name;
  final String? description;
  final String? location;
  final double? priceMin;
  final double? priceMax;
  final String currency;
  final String? url;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ActivityPhoto> photos;

  /// How many of the user's groups it's shared into, when selected.
  final int? sharedGroupCount;

  /// The owner's personal label. Only the owner can see it.
  final String? personalTypeId;
  final String? personalTypeName;

  /// e.g. "SGD 80–150", "Up to SGD 30", "Free"; null when no price is set.
  String? get priceLabel {
    String fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
    final lo = priceMin, hi = priceMax;
    if (lo == null && hi == null) return null;
    if ((lo ?? 0) == 0 && (hi ?? 0) == 0) return 'Free';
    if (lo != null && hi != null) return lo == hi ? '$currency ${fmt(lo)}' : '$currency ${fmt(lo)}–${fmt(hi)}';
    if (hi != null) return 'Up to $currency ${fmt(hi)}';
    return 'From $currency ${fmt(lo!)}';
  }

  /// True when the price range overlaps [min, max] (either bound optional).
  bool fitsBudget({double? min, double? max}) {
    final lo = priceMin ?? priceMax, hi = priceMax ?? priceMin;
    if (lo == null || hi == null) return true;
    if (max != null && lo > max) return false;
    if (min != null && hi < min) return false;
    return true;
  }
}

class ActivityPhoto {
  ActivityPhoto({required this.id, required this.storagePath, required this.position});

  factory ActivityPhoto.fromJson(Map<String, dynamic> j) => ActivityPhoto(
        id: j['id'] as String,
        storagePath: j['storage_path'] as String,
        position: j['position'] as int? ?? 0,
      );

  final String id;
  final String storagePath;
  final int position;
}

/// An activity as shared into one group, with that group's type label.
class GroupActivity {
  GroupActivity({
    required this.groupId,
    required this.typeId,
    this.sharedById,
    required this.sharedAt,
    required this.activity,
    this.typeName,
    this.sharedByUsername,
    this.sourceTypeName,
  });

  static const columns = 'group_id, activity_id, type_id, added_by, added_at, source_type_name, '
      'activities!inner(${Activity.columns}), activity_types(name), '
      'sharer:profiles!group_activities_added_by_fkey(username)';

  factory GroupActivity.fromJson(Map<String, dynamic> j) => GroupActivity(
        groupId: j['group_id'] as String,
        typeId: j['type_id'] as String,
        sharedById: j['added_by'] as String?,
        sharedAt: DateTime.parse(j['added_at'] as String),
        activity: Activity.fromJson(j['activities'] as Map<String, dynamic>),
        typeName: (j['activity_types'] as Map?)?['name'] as String?,
        sharedByUsername: (j['sharer'] as Map?)?['username'] as String?,
        sourceTypeName: j['source_type_name'] as String?,
      );

  final String groupId;
  final String typeId;
  /// Null when the sharer deleted their account.
  final String? sharedById;
  final DateTime sharedAt;
  final Activity activity;
  final String? typeName;
  final String? sharedByUsername;

  /// The owner's label it was filed by, if it wasn't typed by hand.
  final String? sourceTypeName;

  String get activityId => activity.id;
}

/// A row from the change log, with the actor's username resolved.
class ChangeEntry {
  ChangeEntry({
    required this.entityType,
    required this.action,
    required this.actorUsername,
    required this.createdAt,
    this.before,
    this.after,
    this.id,
    this.entityId,
    this.actorId,
    this.subjectName,
    this.personUsername,
    this.fromTypeName,
    this.toTypeName,
    this.eventTitle,
    this.entryId,
    this.entryAllDay = false,
    this.entryDate,
    this.entryStartAt,
    this.entryEndAt,
  });

  /// A row from `list_group_history`, which also names what it's about.
  factory ChangeEntry.fromGroupHistory(Map<String, dynamic> j) {
    DateTime? instant(String key) => j[key] == null ? null : AppClock.inZone(DateTime.parse(j[key] as String));
    return ChangeEntry(
      id: (j['id'] as num).toInt(),
      entityType: j['entity_type'] as String,
      entityId: j['entity_id'] as String?,
      action: j['action'] as String,
      actorId: j['actor_id'] as String?,
      actorUsername: j['actor_username'] as String?,
      createdAt: DateTime.parse(j['created_at'] as String),
      before: j['before'] as Map<String, dynamic>?,
      after: j['after'] as Map<String, dynamic>?,
      subjectName: j['subject_name'] as String?,
      personUsername: j['person_username'] as String?,
      fromTypeName: j['from_type_name'] as String?,
      toTypeName: j['to_type_name'] as String?,
      eventTitle: j['event_title'] as String?,
      entryId: j['entry_id'] as String?,
      entryAllDay: j['entry_all_day'] as bool? ?? false,
      entryDate: j['entry_date'] == null ? null : DateTime.parse(j['entry_date'] as String),
      entryStartAt: instant('entry_start_at'),
      entryEndAt: instant('entry_end_at'),
    );
  }

  final String entityType;
  final String action;
  final String? actorUsername;
  final DateTime createdAt;
  final Map<String, dynamic>? before;
  final Map<String, dynamic>? after;

  // Only set for group history (null elsewhere). Null names mean deleted, or no
  // longer visible to the caller.
  final int? id;
  final String? entityId;
  final String? actorId;

  /// The activity, plan, type or merged label the change is about.
  final String? subjectName;

  /// The member or participant the change is about.
  final String? personUsername;
  final String? fromTypeName;
  final String? toTypeName;

  /// A plan's own name, kept when an activity replaces the event.
  final String? eventTitle;

  /// The plan and its current timing (display zone), for opening it. Null once
  /// the plan is removed; a "no date yet" plan has an id but no date or times.
  final String? entryId;
  final bool entryAllDay;
  final DateTime? entryDate;
  final DateTime? entryStartAt;
  final DateTime? entryEndAt;
}

/// One of the user's own activity labels.
class PersonalType {
  PersonalType({required this.id, required this.name});

  factory PersonalType.fromJson(Map<String, dynamic> j) =>
      PersonalType(id: j['id'] as String, name: j['name'] as String);

  final String id;
  final String name;
}

/// "Activities labelled [sourceName] go into [targetTypeId]" within a group.
class TypeMerge {
  TypeMerge({required this.id, required this.sourceName, required this.targetTypeId});

  factory TypeMerge.fromJson(Map<String, dynamic> j) => TypeMerge(
        id: j['id'] as String,
        sourceName: j['source_name'] as String,
        targetTypeId: j['target_type_id'] as String,
      );

  final String id;
  final String sourceName;
  final String targetTypeId;
}

/// Where an activity with a given label would be filed in a group.
class TypePreview {
  TypePreview({this.typeId, required this.typeName, required this.merged, required this.isNew});

  factory TypePreview.fromJson(Map<String, dynamic> j) => TypePreview(
        typeId: j['type_id'] as String?,
        typeName: j['type_name'] as String,
        merged: j['merged'] as bool,
        isNew: j['is_new'] as bool,
      );

  final String? typeId;
  final String typeName;
  final bool merged;
  final bool isNew;
}

/// A row from `list_notifications`. Plan and group fields are null when the
/// user can no longer see them (left the plan or the group).
class AppNotification {
  AppNotification({
    required this.id,
    required this.kind,
    required this.createdAt,
    this.readAt,
    this.actorName,
    this.groupId,
    this.groupName,
    this.invitationStatus,
    this.entryId,
    this.entryTitle,
    this.entryAllDay = false,
    this.entryDate,
    this.entryStartAt,
    this.entryEndAt,
    this.clashCount = 0,
  });

  factory AppNotification.fromJson(Map<String, dynamic> j) {
    DateTime? instant(String key) => j[key] == null ? null : AppClock.inZone(DateTime.parse(j[key] as String));
    return AppNotification(
      id: j['id'] as String,
      kind: j['kind'] as String,
      createdAt: instant('created_at')!,
      readAt: instant('read_at'),
      actorName: j['actor_name'] as String?,
      groupId: j['group_id'] as String?,
      groupName: j['group_name'] as String?,
      invitationStatus: j['invitation_status'] as String?,
      entryId: j['entry_id'] as String?,
      entryTitle: j['entry_title'] as String?,
      entryAllDay: j['entry_all_day'] as bool? ?? false,
      entryDate: j['entry_date'] == null ? null : DateTime.parse(j['entry_date'] as String),
      entryStartAt: instant('entry_start_at'),
      entryEndAt: instant('entry_end_at'),
      clashCount: j['clash_count'] as int? ?? 0,
    );
  }

  final String id;

  /// `group_invitation`, `added_to_entry` or `schedule_clash`.
  final String kind;
  final DateTime createdAt;
  final DateTime? readAt;

  /// Null when the person who did it deleted their account.
  final String? actorName;
  final String? groupId;
  final String? groupName;

  /// `pending`, `accepted` or `declined` for invitations.
  final String? invitationStatus;
  final String? entryId;
  final String? entryTitle;
  final bool entryAllDay;
  final DateTime? entryDate;
  final DateTime? entryStartAt;
  final DateTime? entryEndAt;

  /// How many of the user's plans this one clashed with.
  final int clashCount;

  bool get unread => readAt == null;
  bool get isInvitation => kind == 'group_invitation';
  bool get isAboutPlan => kind == 'added_to_entry' || kind == 'schedule_clash';
}
