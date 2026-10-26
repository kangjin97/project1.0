import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'activities_repository.dart';
import 'groups_repository.dart';
import 'notifications_repository.dart';
import 'profile_repository.dart';
import 'schedule_repository.dart';

SupabaseClient get _db => Supabase.instance.client;

/// The private Realtime channels the database broadcasts to (#7). A message
/// only names the table that changed; screens re-fetch through RLS.
class RealtimeRepository {
  /// Joins [topic] (`group:<id>` or `user:<id>`) and calls [onChange] with the
  /// changed table for each message. [onRejoin] runs when the channel comes
  /// back after a drop, because messages sent meanwhile are lost.
  /// Returns a function that leaves the channel.
  Future<void> Function() listen(
    String topic, {
    required void Function(String table) onChange,
    required void Function() onRejoin,
  }) {
    var joined = false;
    final channel = _db
        .channel(topic, opts: const RealtimeChannelConfig(private: true))
        .onBroadcast(
          event: 'changed',
          callback: (message) {
            final payload = message['payload'];
            final table = (payload is Map ? payload['table'] : message['table']) as String?;
            if (table != null) onChange(table);
          },
        )
        .subscribe((status, _) {
          if (status != RealtimeSubscribeStatus.subscribed) return;
          if (joined) onRejoin();
          joined = true;
        });
    return () => _db.removeChannel(channel);
  }
}

final realtimeRepositoryProvider = Provider((_) => RealtimeRepository());

/// Re-fetches what other people change while the app is open: listens to the
/// signed-in user's topic and to one topic per group they're in, and follows
/// the group list as they join and leave. Watched by HomeShell, so it runs
/// while signed in and stops on sign-out.
final liveUpdatesProvider = Provider.autoDispose<void>((ref) {
  final me = _db.auth.currentUser?.id;
  if (me == null) return;
  final live = _LiveUpdates(ref, ref.read(realtimeRepositoryProvider))..join('user:$me');
  ref.listen(myGroupsProvider, (_, next) {
    if (next.hasValue) live.setGroups({for (final g in next.requireValue) g.id});
  }, fireImmediately: true);
  ref.onDispose(live.dispose);
});

/// How long to collect messages before re-fetching. A plan with five people
/// arrives as several messages; one refresh covers them all.
const liveUpdateDelay = Duration(milliseconds: 400);

class _LiveUpdates {
  _LiveUpdates(this._ref, this._repo);

  final Ref _ref;
  final RealtimeRepository _repo;
  final _leave = <String, Future<void> Function()>{};
  final _pending = <(String, String)>{};
  Timer? _timer;

  void join(String topic) => _leave[topic] ??= _repo.listen(
        topic,
        onChange: (table) => _queue(topic, table),
        onRejoin: () => _queue(topic, anyTable),
      );

  void setGroups(Set<String> groupIds) {
    final wanted = {for (final id in groupIds) 'group:$id'};
    for (final topic in _leave.keys.where((t) => t.startsWith('group:') && !wanted.contains(t)).toList()) {
      _leave.remove(topic)!();
    }
    wanted.forEach(join);
  }

  void _queue(String topic, String table) {
    _pending.add((topic, table));
    _timer ??= Timer(liveUpdateDelay, _flush);
  }

  void _flush() {
    _timer = null;
    final providers = {for (final (topic, table) in _pending) ...providersAffectedBy(topic, table)};
    _pending.clear();
    providers.forEach(_ref.invalidate);
  }

  void dispose() {
    _timer?.cancel();
    for (final leave in _leave.values) {
      leave();
    }
    _leave.clear();
  }
}

/// Stands for every table, after a reconnect.
const anyTable = '*';

/// The providers to re-fetch when [table] changed for [topic]. Group topics
/// refresh that group's providers; user topics refresh whole families, since
/// one person's change can touch several groups.
List<ProviderOrFamily> providersAffectedBy(String topic, String table) {
  final groupId = topic.startsWith('group:') ? topic.substring('group:'.length) : null;
  ProviderOrFamily inGroup(ProviderOrFamily family, ProviderOrFamily Function(String) one) =>
      groupId == null ? family : one(groupId);

  final groupHistory = inGroup(groupHistoryProvider, groupHistoryProvider.call);
  final groupActivities = inGroup(groupActivitiesProvider, groupActivitiesProvider.call);

  final members = <ProviderOrFamily>[
    myGroupsProvider,
    inGroup(groupProvider, groupProvider.call),
    inGroup(membersProvider, membersProvider.call),
    sharedGroupsProvider,
    myStatsProvider,
    groupHistory,
  ];
  final group = <ProviderOrFamily>[myGroupsProvider, inGroup(groupProvider, groupProvider.call)];
  final shares = <ProviderOrFamily>[
    groupActivities,
    sharedInProvider,
    myActivitiesProvider,
    groupHistory,
    activityHistoryProvider,
  ];
  final activities = <ProviderOrFamily>[
    myActivitiesProvider,
    activityProvider,
    myCopyProvider,
    groupActivities,
    activityHistoryProvider,
    groupHistory,
    scheduleProvider,
  ];
  final types = <ProviderOrFamily>[
    inGroup(typesProvider, typesProvider.call),
    inGroup(mergesProvider, mergesProvider.call),
    groupActivities,
    sharedInProvider,
    groupHistory,
  ];
  final plans = <ProviderOrFamily>[scheduleProvider, entryHistoryProvider, groupHistory, myStatsProvider];
  final notifications = <ProviderOrFamily>[notificationsProvider, unreadCountProvider, invitationsProvider];
  final invitations = <ProviderOrFamily>[
    invitationsProvider,
    notificationsProvider,
    inGroup(sentInvitationsProvider, sentInvitationsProvider.call),
    groupHistory,
  ];
  final links = <ProviderOrFamily>[inGroup(inviteLinksProvider, inviteLinksProvider.call), groupHistory];

  return switch (table) {
    'group_members' => members,
    'groups' => group,
    'group_activities' => shares,
    'activities' || 'activity_photos' => activities,
    'activity_types' || 'type_merges' => types,
    'schedule_entries' || 'schedule_participants' => plans,
    'notifications' => notifications,
    // notificationsProvider too: the Alerts list shows each invitation's status.
    'group_invitations' => invitations,
    'group_invite_links' => links,
    anyTable => {
        ...members,
        ...group,
        ...shares,
        ...activities,
        ...types,
        ...plans,
        ...invitations,
        ...links,
        if (groupId == null) ...notifications,
      }.toList(),
    _ => const [],
  };
}
