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
        invitedBy: (j['inviter'] as Map?)?['username'] as String? ?? 'someone',
      );

  final String id;
  final String groupName;
  final String invitedBy;
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
    required this.sharedById,
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
        sharedById: j['added_by'] as String,
        sharedAt: DateTime.parse(j['added_at'] as String),
        activity: Activity.fromJson(j['activities'] as Map<String, dynamic>),
        typeName: (j['activity_types'] as Map?)?['name'] as String?,
        sharedByUsername: (j['sharer'] as Map?)?['username'] as String?,
        sourceTypeName: j['source_type_name'] as String?,
      );

  final String groupId;
  final String typeId;
  final String sharedById;
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
  });

  final String entityType;
  final String action;
  final String? actorUsername;
  final DateTime createdAt;
  final Map<String, dynamic>? before;
  final Map<String, dynamic>? after;
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
