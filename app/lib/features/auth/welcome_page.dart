import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/app_clock.dart';
import '../../data/auth_repository.dart';
import '../../data/groups_repository.dart';
import '../../data/models.dart';
import '../../data/profile_repository.dart';
import '../../widgets/dialogs.dart';

final _usernamePattern = RegExp(r'^[a-z0-9_]{3,30}$');

/// A username to suggest from a name ("Kang Jin" → "kang_jin") or, failing
/// that, the email's first part. Always matches the sign-up rules.
String usernameBase(String? name, String? email) {
  String clean(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  var base = clean(name ?? '');
  if (base.length < 3) base = clean((email ?? '').split('@').first);
  if (base.length < 3) base = 'user_$base';
  base = base.length > 30 ? base.substring(0, 30) : base;
  return base.replaceAll(RegExp(r'_+$'), '').padRight(3, '0');
}

/// Suggestions to try in order: the base, then numbered ones, then a random tail.
List<String> usernameCandidates(String base, {Random? random}) {
  final short = base.length > 28 ? base.substring(0, 28) : base;
  final tail = (random ?? Random()).nextInt(9000) + 1000;
  final four = base.length > 26 ? base.substring(0, 26) : base;
  return [base, for (var i = 2; i <= 9; i++) '$short$i', '$four$tail'];
}

/// First Google sign-in (#87): Google gives no username, so the person picks one
/// (a suggestion is filled in), checks their name, and can take their Google
/// photo. Also sets the device's time zone, as the sign-up form does.
class WelcomePage extends ConsumerStatefulWidget {
  const WelcomePage({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  ConsumerState<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends ConsumerState<WelcomePage> {
  final _form = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _displayName = TextEditingController();
  Profile? _profile;
  String? _photoUrl;
  bool _usePhoto = true;
  bool _busy = false;
  String? _error;

  String get _me => Supabase.instance.client.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _username.dispose();
    _displayName.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final profiles = ref.read(profileRepositoryProvider);
    try {
      final profile = await profiles.profile(_me);
      final email = Supabase.instance.client.auth.currentUser?.email;
      var suggestion = usernameBase(profile.displayName, email);
      for (final c in usernameCandidates(suggestion)) {
        if (await profiles.usernameAvailable(c)) {
          suggestion = c;
          break;
        }
      }
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _username.text = suggestion;
        _displayName.text = profile.displayName ?? '';
        // Only offer the photo when there isn't one yet.
        _photoUrl = profile.avatarPath == null ? ref.read(authRepositoryProvider).googlePhotoUrl : null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _continue() async {
    if (!_form.currentState!.validate()) return;
    final profiles = ref.read(profileRepositoryProvider);
    final username = _username.text.trim().toLowerCase();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (username != _profile!.username && !await profiles.usernameAvailable(username)) {
        setState(() => _error = 'That username is taken.');
        return;
      }
      // Saving the username is what tells the database this step is done.
      await profiles.update(username: username, displayName: _displayName.text, bio: _profile!.bio);
      try {
        await ref.read(timezoneProvider.notifier).change(AppClock.deviceZone);
      } catch (_) {
        // The zone can be changed on the profile later; don't block sign-in on it.
      }
      if (_usePhoto && _photoUrl != null) {
        try {
          await profiles.copyAvatarFrom(_photoUrl!);
        } catch (_) {
          if (mounted) showMessage(context, 'Couldn’t copy your Google photo. You can add one on your profile.');
        }
      }
      ref.invalidate(profileProvider(_me));
      widget.onDone();
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.groups_2_outlined, size: 56, color: theme.colorScheme.primary),
                  const SizedBox(height: 12),
                  Text('Welcome to EasyPlan', textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 4),
                  Text('Pick a username so friends can find you.',
                      textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 24),
                  if (_profile == null && _error == null)
                    const Center(child: CircularProgressIndicator())
                  else if (_profile != null) ...[
                    TextFormField(
                      controller: _username,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        helperText: 'Lowercase letters, numbers and _',
                        border: OutlineInputBorder(),
                      ),
                      autocorrect: false,
                      validator: (v) => _usernamePattern.hasMatch((v ?? '').trim().toLowerCase())
                          ? null
                          : '3–30 characters: a–z, 0–9 or _',
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _displayName,
                      maxLength: 50,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Display name (optional)', border: OutlineInputBorder()),
                    ),
                    if (_photoUrl != null)
                      CheckboxListTile(
                        value: _usePhoto,
                        onChanged: _busy ? null : (v) => setState(() => _usePhoto = v ?? false),
                        contentPadding: EdgeInsets.zero,
                        secondary: CircleAvatar(backgroundImage: NetworkImage(_photoUrl!)),
                        title: const Text('Use your Google photo'),
                      ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy || _profile == null ? null : _continue,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: _busy
                          ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Continue'),
                    ),
                  ),
                  TextButton(
                    onPressed: _busy ? null : () => Supabase.instance.client.auth.signOut(),
                    child: const Text('Not you? Sign out'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
