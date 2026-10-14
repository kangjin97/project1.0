import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config.dart';
import '../../data/app_clock.dart';
import '../../data/groups_repository.dart';
import '../../data/models.dart';
import '../../widgets/async_body.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/user_avatar.dart';
import '../notifications/notifications_page.dart' show timeAgo;
import '../schedule/schedule_widgets.dart' show formatShortDay;
import 'group_activities_tab.dart';
import 'group_schedule_tab.dart';
import 'group_types_tab.dart';

class GroupPage extends ConsumerWidget {
  const GroupPage({super.key, required this.groupId});

  final String groupId;

  Future<void> _rename(BuildContext context, WidgetRef ref, Group group) async {
    final name = await promptText(context, title: 'Rename group', label: 'Group name', action: 'Save', initial: group.name);
    if (name == null || name.trim().isEmpty || !context.mounted) return;
    try {
      await ref.read(groupsRepositoryProvider).renameGroup(groupId, name);
      ref.invalidate(groupProvider(groupId));
      ref.invalidate(myGroupsProvider);
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _leave(BuildContext context, WidgetRef ref, Group group) async {
    final ok = await confirm(context,
        title: 'Leave ${group.name}?',
        message: 'You’ll stop seeing this group’s activities and schedule.',
        action: 'Leave');
    if (!ok || !context.mounted) return;
    try {
      await ref.read(groupsRepositoryProvider).leaveGroup(groupId);
      ref.invalidate(myGroupsProvider);
      if (context.mounted) context.go('/groups');
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final group = ref.watch(groupProvider(groupId));
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(group.value?.name ?? ''),
          actions: [
            if (group.value case final g?)
              PopupMenuButton<String>(
                onSelected: (v) => switch (v) {
                  'rename' => _rename(context, ref, g),
                  'history' => context.push('/groups/$groupId/history'),
                  _ => _leave(context, ref, g),
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'rename', child: Text('Rename group')),
                  PopupMenuItem(value: 'history', child: Text('History')),
                  PopupMenuItem(value: 'leave', child: Text('Leave group')),
                ],
              ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Activities'),
              Tab(text: 'Schedule'),
              Tab(text: 'Members'),
              Tab(text: 'Types'),
            ],
          ),
        ),
        body: AsyncBody(
          value: group,
          builder: (_) => TabBarView(
            children: [
              GroupActivitiesTab(groupId: groupId),
              GroupScheduleTab(groupId: groupId),
              _MembersTab(groupId: groupId),
              GroupTypesTab(groupId: groupId),
            ],
          ),
        ),
      ),
    );
  }
}

// ---- Members ----------------------------------------------------------------

class _MembersTab extends ConsumerWidget {
  const _MembersTab({required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = Supabase.instance.client.auth.currentUser!.id;
    final members = ref.watch(membersProvider(groupId));
    return AsyncBody(
      value: members,
      builder: (list) {
        final iAmOwner = list.any((m) => m.profile.id == me && m.isOwner);
        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: () => showModalBottomSheet(
                      context: context,
                      useRootNavigator: true,
                      isScrollControlled: true,
                      showDragHandle: true,
                      builder: (_) => _InviteSheet(groupId: groupId),
                    ),
                    icon: const Icon(Icons.person_add_alt),
                    label: const Text('Invite people'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _shareLink(context, ref),
                    icon: const Icon(Icons.link),
                    label: const Text('Invite link'),
                  ),
                ],
              ),
            ),
            _InviteLinksSection(groupId: groupId),
            _SentInvitationsSection(groupId: groupId),
            _SectionHeading('Members · ${list.length}'),
            for (final m in list)
              ListTile(
                onTap: () => context.push(m.profile.id == me ? '/profile' : '/people/${m.profile.id}'),
                leading: UserAvatar(label: m.profile.label, avatarPath: m.profile.avatarPath),
                title: Text(m.profile.id == me ? '${m.profile.label} (you)' : m.profile.label),
                subtitle: Text('@${m.profile.username}'),
                trailing: m.isOwner
                    ? const Chip(label: Text('Owner'))
                    : iAmOwner
                        ? IconButton(
                            tooltip: 'Remove from group',
                            icon: const Icon(Icons.person_remove_outlined),
                            onPressed: () async {
                              final ok = await confirm(context,
                                  title: 'Remove ${m.profile.label}?',
                                  message: 'They can rejoin with a new invite.',
                                  action: 'Remove');
                              if (!ok) return;
                              try {
                                await ref.read(groupsRepositoryProvider).removeMember(groupId, m.profile.id);
                                ref.invalidate(membersProvider(groupId));
                              } catch (e) {
                                if (context.mounted) showError(context, e);
                              }
                            },
                          )
                        : null,
              ),
          ],
        );
      },
    );
  }

  Future<void> _shareLink(BuildContext context, WidgetRef ref) async {
    try {
      final token = await ref.read(groupsRepositoryProvider).createInviteLink(groupId);
      ref.invalidate(inviteLinksProvider(groupId));
      ref.invalidate(groupHistoryProvider(groupId));
      if (!context.mounted) return;
      await _showInviteLinkDialog(context, token, expiresAt: null);
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }
}

/// The code and link for an invite link, with copy buttons. [expiresAt] null
/// means a link just made (they last 7 days).
Future<void> _showInviteLinkDialog(BuildContext context, String token, {required DateTime? expiresAt}) {
  final link = AppConfig.inviteLink(token);
  final until = expiresAt == null
      ? 'for the next 7 days'
      : 'until ${DateFormat('EEE d MMM, h:mm a').format(AppClock.inZone(expiresAt))}';
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Invite link'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Anyone with this code can join $until.'),
          const SizedBox(height: 12),
          SelectableText(token, style: const TextStyle(fontFamily: 'monospace')),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: token));
            Navigator.pop(context);
            showMessage(context, 'Code copied');
          },
          child: const Text('Copy code'),
        ),
        FilledButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: link));
            Navigator.pop(context);
            showMessage(context, 'Link copied');
          },
          child: const Text('Copy link'),
        ),
      ],
    ),
  );
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(text, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
    );
  }
}

/// Links that still let people join, with who made them, expiry and uses.
/// Tap to copy again; any member can revoke. Hidden when there are none.
class _InviteLinksSection extends ConsumerWidget {
  const _InviteLinksSection({required this.groupId});

  final String groupId;

  Future<void> _revoke(BuildContext context, WidgetRef ref, InviteLink link) async {
    final ok = await confirm(context,
        title: 'Revoke this link?',
        message: 'Nobody new can join with it. People who already joined stay in the group.',
        action: 'Revoke');
    if (!ok || !context.mounted) return;
    try {
      await ref.read(groupsRepositoryProvider).revokeInviteLink(link.id);
      ref.invalidate(inviteLinksProvider(groupId));
      ref.invalidate(groupHistoryProvider(groupId));
      if (context.mounted) showMessage(context, 'Link revoked');
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(timezoneProvider);
    final now = AppClock.now();
    final links = [...?ref.watch(inviteLinksProvider(groupId)).value?.where((l) => l.isActiveAt(now))];
    if (links.isEmpty) return const SizedBox.shrink();
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeading('Active invite links · ${links.length}'),
        for (final l in links)
          ListTile(
            leading: const Icon(Icons.link),
            title: Text('Code ${l.token.substring(0, 6)}…', style: const TextStyle(fontFamily: 'monospace')),
            subtitle: Text(
              [
                'By ${l.createdByUsername == null ? 'a deleted user' : '@${l.createdByUsername}'}',
                if (l.expiresAt != null) 'until ${formatShortDay(AppClock.inZone(l.expiresAt!))}',
                l.maxUses == null ? '${l.useCount} joined' : '${l.useCount} of ${l.maxUses} joined',
              ].join(' · '),
              style: muted,
            ),
            onTap: () => _showInviteLinkDialog(context, l.token, expiresAt: l.expiresAt),
            trailing: TextButton(onPressed: () => _revoke(context, ref, l), child: const Text('Revoke')),
          ),
      ],
    );
  }
}

/// Invitations still waiting for an answer; any member can cancel one.
/// Hidden when there are none.
class _SentInvitationsSection extends ConsumerWidget {
  const _SentInvitationsSection({required this.groupId});

  final String groupId;

  Future<void> _cancel(BuildContext context, WidgetRef ref, SentInvitation inv) async {
    final ok = await confirm(context,
        title: 'Cancel the invitation for @${inv.invitee.username}?',
        message: 'They won’t be able to join with it, and their alert will say it was cancelled.',
        action: 'Cancel invitation',
        dismiss: 'Keep it');
    if (!ok || !context.mounted) return;
    try {
      await ref.read(groupsRepositoryProvider).cancelInvitation(inv.id);
      ref.invalidate(sentInvitationsProvider(groupId));
      ref.invalidate(groupHistoryProvider(groupId));
      if (context.mounted) showMessage(context, 'Invitation cancelled');
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invitations = ref.watch(sentInvitationsProvider(groupId)).value ?? const <SentInvitation>[];
    if (invitations.isEmpty) return const SizedBox.shrink();
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);
    final now = AppClock.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeading('Waiting for an answer · ${invitations.length}'),
        for (final inv in invitations)
          ListTile(
            leading: UserAvatar(label: inv.invitee.label, avatarPath: inv.invitee.avatarPath),
            title: Text(inv.invitee.label),
            subtitle: Text(
              '@${inv.invitee.username} · invited by '
              '${inv.invitedByUsername == null ? 'a deleted user' : '@${inv.invitedByUsername}'} · '
              '${timeAgo(inv.createdAt, now)}',
              style: muted,
            ),
            trailing: TextButton(onPressed: () => _cancel(context, ref, inv), child: const Text('Cancel')),
          ),
      ],
    );
  }
}

class _InviteSheet extends ConsumerStatefulWidget {
  const _InviteSheet({required this.groupId});

  final String groupId;

  @override
  ConsumerState<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends ConsumerState<_InviteSheet> {
  final _query = TextEditingController();
  Timer? _debounce;
  List<Profile> _results = [];
  final _invited = <String>{};
  bool _searching = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      setState(() => _searching = true);
      try {
        final results = await ref.read(groupsRepositoryProvider).searchUsers(q);
        if (mounted && q == _query.text) setState(() => _results = results);
      } finally {
        if (mounted) setState(() => _searching = false);
      }
    });
  }

  Future<void> _invite(Profile p) async {
    try {
      await ref.read(groupsRepositoryProvider).invite(widget.groupId, p.id);
      ref.invalidate(sentInvitationsProvider(widget.groupId));
      ref.invalidate(groupHistoryProvider(widget.groupId));
      setState(() => _invited.add(p.id));
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final members = ref.watch(membersProvider(widget.groupId)).value ?? const [];
    final memberIds = {for (final m in members) m.profile.id};
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: 420,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _query,
                autofocus: true,
                onChanged: _onChanged,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  labelText: 'Username or email',
                  border: const OutlineInputBorder(),
                  suffixIcon: _searching
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : null,
                ),
              ),
            ),
            Expanded(
              child: _results.isEmpty
                  ? Center(
                      child: Text(
                        _query.text.trim().length < 2
                            ? 'Search by username, or enter someone’s full email.'
                            : 'No one found.',
                      ),
                    )
                  : ListView(
                      children: [
                        for (final p in _results)
                          ListTile(
                            leading: UserAvatar(label: p.label, avatarPath: p.avatarPath),
                            title: Text(p.label),
                            subtitle: Text('@${p.username}'),
                            trailing: memberIds.contains(p.id)
                                ? const Text('Member')
                                : _invited.contains(p.id)
                                    ? const Text('Invited')
                                    : FilledButton.tonal(onPressed: () => _invite(p), child: const Text('Invite')),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
