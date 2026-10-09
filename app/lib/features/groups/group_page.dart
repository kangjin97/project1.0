import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/groups_repository.dart';
import '../../data/models.dart';
import '../../widgets/async_body.dart';
import '../../widgets/dialogs.dart';
import 'group_activities_tab.dart';
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
                onSelected: (v) => v == 'rename' ? _rename(context, ref, g) : _leave(context, ref, g),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'rename', child: Text('Rename group')),
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
              const EmptyState(
                icon: Icons.calendar_month_outlined,
                message: 'The group’s plans and events will show up here.',
              ),
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
            for (final m in list)
              ListTile(
                leading: CircleAvatar(child: Text(m.profile.label.characters.first.toUpperCase())),
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
      if (!context.mounted) return;
      final link = '${Uri.base.origin}/#/join/$token';
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Invite link'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Anyone with this code can join for the next 7 days.'),
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
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
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
