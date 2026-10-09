import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/activities_repository.dart';
import '../../data/groups_repository.dart';
import '../../data/models.dart';
import '../../data/profile_repository.dart';
import '../../data/schedule_repository.dart';
import '../../widgets/dialogs.dart';

final _usernamePattern = RegExp(r'^[a-z0-9_]{3,30}$');

/// Opens the editor for the user's name, username and bio. True when saved.
Future<bool> showEditProfile(BuildContext context, Profile profile) async {
  final saved = await Navigator.of(context, rootNavigator: true).push<bool>(
    MaterialPageRoute(fullscreenDialog: true, builder: (_) => EditProfilePage(profile: profile)),
  );
  return saved ?? false;
}

enum _Availability { unchanged, checking, available, taken, invalid }

class EditProfilePage extends ConsumerStatefulWidget {
  const EditProfilePage({super.key, required this.profile});

  final Profile profile;

  @override
  ConsumerState<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends ConsumerState<EditProfilePage> {
  late final _displayName = TextEditingController(text: widget.profile.displayName);
  late final _username = TextEditingController(text: widget.profile.username);
  late final _bio = TextEditingController(text: widget.profile.bio);
  _Availability _availability = _Availability.unchanged;
  Timer? _debounce;
  bool _saving = false;

  @override
  void dispose() {
    _debounce?.cancel();
    for (final c in [_displayName, _username, _bio]) {
      c.dispose();
    }
    super.dispose();
  }

  void _onUsernameChanged(String raw) {
    _debounce?.cancel();
    final value = raw.trim().toLowerCase();
    if (value == widget.profile.username) {
      setState(() => _availability = _Availability.unchanged);
      return;
    }
    if (!_usernamePattern.hasMatch(value)) {
      setState(() => _availability = _Availability.invalid);
      return;
    }
    setState(() => _availability = _Availability.checking);
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      try {
        final free = await ref.read(profileRepositoryProvider).usernameAvailable(value);
        if (mounted && _username.text.trim().toLowerCase() == value) {
          setState(() => _availability = free ? _Availability.available : _Availability.taken);
        }
      } catch (_) {
        if (mounted) setState(() => _availability = _Availability.unchanged);
      }
    });
  }

  Future<void> _save() async {
    if (_availability == _Availability.invalid || _availability == _Availability.taken) {
      showMessage(context, 'Choose a different username first.');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(profileRepositoryProvider).update(
            username: _username.text,
            displayName: _displayName.text,
            bio: _bio.text,
          );
      // Names appear in member lists, plans and activity cards.
      ref.invalidate(profileProvider(widget.profile.id));
      ref.invalidate(membersProvider);
      ref.invalidate(groupActivitiesProvider);
      ref.invalidate(scheduleProvider);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (String? helper, String? error, Widget? suffix) = switch (_availability) {
      _Availability.unchanged => ('Lowercase letters, numbers and _', null, null),
      _Availability.checking => (
          'Checking…',
          null,
          const Padding(
            padding: EdgeInsets.all(12),
            child: SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        ),
      _Availability.available => ('Available', null, Icon(Icons.check_circle, color: scheme.primary)),
      _Availability.taken => (null, 'That username is taken', Icon(Icons.cancel, color: scheme.error)),
      _Availability.invalid => (null, '3–30 characters: a–z, 0–9 or _', null),
    };
    const gap = SizedBox(height: 16);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit profile'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _displayName,
                    textCapitalization: TextCapitalization.words,
                    maxLength: 50,
                    decoration: const InputDecoration(
                      labelText: 'Display name',
                      helperText: 'Shown instead of your username where there’s room',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  gap,
                  TextField(
                    controller: _username,
                    autocorrect: false,
                    onChanged: _onUsernameChanged,
                    decoration: InputDecoration(
                      labelText: 'Username',
                      prefixText: '@',
                      helperText: helper,
                      errorText: error,
                      suffixIcon: suffix,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  gap,
                  TextField(
                    controller: _bio,
                    minLines: 3,
                    maxLines: 5,
                    maxLength: 160,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Bio',
                      hintText: 'A line or two about you',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
