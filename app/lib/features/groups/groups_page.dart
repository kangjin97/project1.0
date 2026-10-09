import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/groups_repository.dart';
import '../../widgets/async_body.dart';
import '../../widgets/dialogs.dart';

class GroupsPage extends ConsumerWidget {
  const GroupsPage({super.key});

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final name = await promptText(context, title: 'New group', label: 'Group name', action: 'Create');
    if (name == null || name.trim().isEmpty || !context.mounted) return;
    try {
      final id = await ref.read(groupsRepositoryProvider).createGroup(name);
      ref.invalidate(myGroupsProvider);
      if (context.mounted) context.go('/groups/$id');
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _joinWithCode(BuildContext context) async {
    final code = await promptText(context, title: 'Join a group', label: 'Invite code', action: 'Next');
    if (code == null || code.trim().isEmpty || !context.mounted) return;
    // Accept either the bare code or a pasted link.
    final token = code.trim().split('/').last;
    context.push('/join/$token');
  }

  Future<void> _respond(BuildContext context, WidgetRef ref, String id, bool accept) async {
    try {
      await ref.read(groupsRepositoryProvider).respond(id, accept: accept);
      ref.invalidate(invitationsProvider);
      ref.invalidate(myGroupsProvider);
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(myGroupsProvider);
    final invitations = ref.watch(invitationsProvider).value ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Groups'),
        actions: [
          TextButton.icon(
            onPressed: () => _joinWithCode(context),
            icon: const Icon(Icons.link),
            label: const Text('Join with code'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _create(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('New group'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(invitationsProvider);
          ref.invalidate(myGroupsProvider);
          await ref.read(myGroupsProvider.future);
        },
        child: AsyncBody(
          value: groups,
          builder: (list) => ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              if (invitations.isNotEmpty) ...[
                const _SectionHeader('Invitations'),
                for (final inv in invitations)
                  Card(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: ListTile(
                      leading: const Icon(Icons.mail_outline),
                      title: Text(inv.groupName),
                      subtitle: Text('Invited by @${inv.invitedBy}'),
                      trailing: Wrap(
                        spacing: 4,
                        children: [
                          TextButton(onPressed: () => _respond(context, ref, inv.id, false), child: const Text('Decline')),
                          FilledButton(onPressed: () => _respond(context, ref, inv.id, true), child: const Text('Join')),
                        ],
                      ),
                    ),
                  ),
              ],
              if (list.isEmpty)
                const EmptyState(
                  icon: Icons.groups_outlined,
                  message: 'No groups yet. Create one, or join with an invite code from a friend.',
                )
              else ...[
                const _SectionHeader('Your groups'),
                for (final g in list)
                  ListTile(
                    leading: CircleAvatar(child: Text(g.name.characters.first.toUpperCase())),
                    title: Text(g.name),
                    subtitle: Text('${g.memberCount} member${g.memberCount == 1 ? '' : 's'}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.go('/groups/${g.id}'),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall),
      );
}
