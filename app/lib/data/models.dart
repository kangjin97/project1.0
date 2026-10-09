class Profile {
  Profile({required this.id, required this.username, this.displayName});

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        id: j['id'] as String,
        username: j['username'] as String,
        displayName: j['display_name'] as String?,
      );

  final String id;
  final String username;
  final String? displayName;

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
    required this.createdAt,
    this.photoUrls = const [],
  });

  factory Activity.fromJson(Map<String, dynamic> j) => Activity(
        id: j['id'] as String,
        ownerId: j['owner_id'] as String,
        name: j['name'] as String,
        description: j['description'] as String?,
        createdAt: DateTime.parse(j['created_at'] as String),
      );

  final String id;
  final String ownerId;
  final String name;
  final String? description;
  final DateTime createdAt;
  final List<String> photoUrls;
}

class GroupActivity {
  GroupActivity({
    required this.groupId,
    required this.activityId,
    required this.typeId,
    required this.sharedById,
    required this.sharedAt,
    required this.activity,
    this.typeName,
    this.sharedByUsername,
  });

  factory GroupActivity.fromJson(Map<String, dynamic> j) => GroupActivity(
        groupId: j['group_id'] as String,
        activityId: j['activity_id'] as String,
        typeId: j['type_id'] as String,
        sharedById: j['added_by'] as String,
        sharedAt: DateTime.parse(j['added_at'] as String),
        activity: Activity.fromJson(j['activities'] as Map<String, dynamic>),
        typeName: (j['activity_types'] as Map?)?['name'] as String?,
        sharedByUsername: (j['sharer'] as Map?)?['username'] as String?,
      );

  final String groupId;
  final String activityId;
  final String typeId;
  final String sharedById;
  final DateTime sharedAt;
  final Activity activity;
  final String? typeName;
  final String? sharedByUsername;
}
