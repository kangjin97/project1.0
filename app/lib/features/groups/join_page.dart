import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/groups_repository.dart';
import '../../widgets/async_body.dart';
import '../../widgets/dialogs.dart';

final _previewProvider = FutureProvider.autoDispose
    .family((ref, String token) => ref.watch(groupsRepositoryProvider).previewLink(token));

class JoinPage extends ConsumerWidget {
  const JoinPage({super.key, required this.token});

  final String token;

  Future<void> _join(BuildContext context, WidgetRef ref) async {
    try {
      final id = await ref.read(groupsRepositoryProvider).joinViaLink(token);
      ref.invalidate(myGroupsProvider);
      if (context.mounted) context.go('/groups/$id');
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Join a group')),
      body: AsyncBody(
        value: ref.watch(_previewProvider(token)),
        builder: (preview) {
          if (preview == null) {
            return const EmptyState(
              icon: Icons.link_off,
              message: 'This invite is invalid or has expired. Ask for a new one.',
            );
          }
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(radius: 32, child: Text(preview.name.characters.first.toUpperCase())),
                  const SizedBox(height: 16),
                  Text(preview.name, style: theme.textTheme.headlineSmall),
                  Text('${preview.members} member${preview.members == 1 ? '' : 's'}'),
                  const SizedBox(height: 24),
                  FilledButton(onPressed: () => _join(context, ref), child: const Text('Join group')),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
