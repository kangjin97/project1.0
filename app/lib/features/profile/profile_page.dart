import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/app_clock.dart';
import '../../data/groups_repository.dart';
import '../../data/models.dart';
import '../../data/profile_repository.dart';
import '../../data/schedule_repository.dart';
import '../../widgets/async_body.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/user_avatar.dart';
import 'edit_profile_page.dart';
import 'timezone_picker.dart';

/// The signed-in user's own profile, stats and account settings.
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  Future<void> _changePhoto(BuildContext context, WidgetRef ref, Profile p) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose a photo'),
              onTap: () => Navigator.pop(context, 'pick'),
            ),
            if (p.avatarPath != null)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Remove photo'),
                onTap: () => Navigator.pop(context, 'remove'),
              ),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    final repo = ref.read(profileRepositoryProvider);
    try {
      if (choice == 'remove') {
        await repo.removeAvatar(p.avatarPath!);
      } else {
        final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 512, imageQuality: 85);
        if (file == null) return;
        final ext = file.name.contains('.') ? file.name.split('.').last : 'jpg';
        await repo.setAvatar(await file.readAsBytes(), extension: ext, previousPath: p.avatarPath);
      }
      ref.invalidate(profileProvider(p.id));
      ref.invalidate(membersProvider);
      ref.invalidate(scheduleProvider);
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _changeEmail(BuildContext context, WidgetRef ref) async {
    final email = await promptText(context, title: 'Change email', label: 'New email', action: 'Send link');
    if (email == null || !email.contains('@') || !context.mounted) return;
    try {
      await ref.read(profileRepositoryProvider).changeEmail(email);
      if (context.mounted) {
        showMessage(context, 'Check your inbox at ${email.trim()} to confirm the change.');
      }
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = Supabase.instance.client.auth.currentUser!;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: AsyncBody(
        value: ref.watch(profileProvider(me.id)),
        builder: (p) => ListView(
          padding: const EdgeInsets.only(bottom: 48),
          children: [
            const SizedBox(height: 16),
            Center(
              child: Stack(
                children: [
                  GestureDetector(
                    onTap: () => _changePhoto(context, ref, p),
                    child: UserAvatar(label: p.label, avatarPath: p.avatarPath, radius: 52),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: IconButton.filledTonal(
                      tooltip: 'Change photo',
                      onPressed: () => _changePhoto(context, ref, p),
                      icon: const Icon(Icons.photo_camera_outlined, size: 20),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(p.label, textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
            Text('@${p.username}', textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 12, 32, 0),
              child: p.bio == null
                  ? Center(
                      child: TextButton.icon(
                        onPressed: () => showEditProfile(context, p),
                        icon: const Icon(Icons.add),
                        label: const Text('Add a bio'),
                      ),
                    )
                  : Text(p.bio!, textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
            ),
            const SizedBox(height: 12),
            Center(
              child: OutlinedButton.icon(
                onPressed: () => showEditProfile(context, p),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit profile'),
              ),
            ),
            const SizedBox(height: 20),
            const _Stats(),
            const Divider(height: 40),
            _SectionTitle('Your groups'),
            _GroupsList(userId: me.id, emptyText: 'You’re not in any groups yet.'),
            const Divider(height: 40),
            _SectionTitle('Account'),
            ListTile(
              leading: const Icon(Icons.mail_outline),
              title: Text(me.email ?? ''),
              subtitle: me.newEmail == null ? const Text('Email') : Text('Waiting to confirm ${me.newEmail}'),
              trailing: TextButton(onPressed: () => _changeEmail(context, ref), child: const Text('Change')),
            ),
            ListTile(
              leading: const Icon(Icons.lock_outline),
              title: const Text('Password'),
              trailing: TextButton(
                onPressed: () => showDialog<void>(context: context, builder: (_) => const _ChangePasswordDialog()),
                child: const Text('Change'),
              ),
            ),
            const _TimezoneTile(),
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
                onPressed: () => Supabase.instance.client.auth.signOut(),
                icon: const Icon(Icons.logout),
                label: const Text('Sign out'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows the display zone with its offset; tap to change.
class _TimezoneTile extends ConsumerWidget {
  const _TimezoneTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zone = ref.watch(timezoneProvider);
    final city = zone.contains('/') ? zone.substring(zone.lastIndexOf('/') + 1).replaceAll('_', ' ') : zone;
    final region = zone.contains('/') ? zone.substring(0, zone.indexOf('/')) : null;
    return ListTile(
      leading: const Icon(Icons.public),
      title: Text([city, ?region].join(' · ')),
      subtitle: Text(
        AppClock.differsFromDevice
            ? '${AppClock.offsetLabel()} · Time zone. This device is on ${AppClock.offsetLabel(AppClock.deviceZone)}.'
            : '${AppClock.offsetLabel()} · Time zone for plans and calendars',
      ),
      trailing: TextButton(onPressed: () => showTimezonePicker(context), child: const Text('Change')),
      onTap: () => showTimezonePicker(context),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );
}

class _Stats extends ConsumerWidget {
  const _Stats();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(myStatsProvider).value;
    Widget tile(String label, int? value, String route) => Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => context.go(route),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: [
                  Text(value?.toString() ?? '–', style: Theme.of(context).textTheme.headlineSmall),
                  Text(label, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          tile('Groups', stats?.groups, '/groups'),
          tile('Activities', stats?.activities, '/activities'),
          tile('Upcoming plans', stats?.upcomingPlans, '/schedule'),
        ],
      ),
    );
  }
}

/// Groups the viewer shares with [userId] (all their own groups on their profile).
class _GroupsList extends ConsumerWidget {
  const _GroupsList({required this.userId, required this.emptyText});

  final String userId;
  final String emptyText;

  @override
  Widget build(BuildContext context, WidgetRef ref) => AsyncBody(
        value: ref.watch(sharedGroupsProvider(userId)),
        builder: (groups) => groups.isEmpty
            ? Padding(padding: const EdgeInsets.all(16), child: Text(emptyText))
            : Column(
                children: [
                  for (final g in groups)
                    ListTile(
                      leading: CircleAvatar(child: Text(g.name.characters.first.toUpperCase())),
                      title: Text(g.name),
                      subtitle: Text('${g.members} member${g.members == 1 ? '' : 's'}'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.go('/groups/${g.groupId}'),
                    ),
                ],
              ),
      );
}

/// Someone else's profile: picture, name, bio and the groups you share.
class PersonPage extends ConsumerWidget {
  const PersonPage({super.key, required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(),
      body: AsyncBody(
        value: ref.watch(profileProvider(userId)),
        builder: (p) => ListView(
          padding: const EdgeInsets.only(bottom: 48),
          children: [
            const SizedBox(height: 8),
            Center(child: UserAvatar(label: p.label, avatarPath: p.avatarPath, radius: 52)),
            const SizedBox(height: 12),
            Text(p.label, textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
            Text('@${p.username}', textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
            if (p.bio != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 12, 32, 0),
                child: Text(p.bio!, textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
              ),
            const Divider(height: 40),
            const _SectionTitle('Groups you share'),
            _GroupsList(userId: userId, emptyText: 'You don’t share any groups.'),
          ],
        ),
      ),
    );
  }
}

class _ChangePasswordDialog extends ConsumerStatefulWidget {
  const _ChangePasswordDialog();

  @override
  ConsumerState<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends ConsumerState<_ChangePasswordDialog> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_current, _next, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(profileRepositoryProvider).changePassword(current: _current.text, next: _next.text);
      if (mounted) {
        Navigator.pop(context);
        showMessage(context, 'Password changed');
      }
    } on AuthException catch (e) {
      setState(() {
        _busy = false;
        _error = e.message.toLowerCase().contains('invalid') ? 'Your current password is wrong.' : e.message;
      });
    } catch (e) {
      setState(() {
        _busy = false;
        _error = friendlyError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    InputDecoration field(String label) => InputDecoration(labelText: label, border: const OutlineInputBorder());
    return AlertDialog(
      title: const Text('Change password'),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _current,
              obscureText: true,
              decoration: field('Current password'),
              validator: (v) => (v ?? '').isEmpty ? 'Enter your current password' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _next,
              obscureText: true,
              decoration: field('New password'),
              validator: (v) => (v ?? '').length >= 8 ? null : 'At least 8 characters',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _confirm,
              obscureText: true,
              decoration: field('Repeat new password'),
              validator: (v) => v == _next.text ? null : 'Doesn’t match',
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _busy ? null : _submit, child: const Text('Change')),
      ],
    );
  }
}
