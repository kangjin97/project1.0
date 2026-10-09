import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/groups_repository.dart';

final _usernamePattern = RegExp(r'^[a-z0-9_]{3,30}$');

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _username = TextEditingController();
  final _displayName = TextEditingController();
  bool _signUp = false;
  bool _busy = false;
  String? _error;

  SupabaseClient get _db => Supabase.instance.client;

  @override
  void dispose() {
    for (final c in [_email, _password, _username, _displayName]) {
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
      if (_signUp) {
        final username = _username.text.trim().toLowerCase();
        final available = await _db.rpc('username_available', params: {'p_username': username}) as bool;
        if (!available) {
          setState(() => _error = 'That username is taken.');
          return;
        }
        await _db.auth.signUp(
          email: _email.text.trim(),
          password: _password.text,
          data: {'username': username, 'display_name': _displayName.text.trim()},
        );
      } else {
        await _db.auth.signInWithPassword(email: _email.text.trim(), password: _password.text);
      }
      // The router redirects once the session changes.
    } catch (e) {
      setState(() => _error = friendlyError(e));
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
                  Text('Group Planner', textAlign: TextAlign.center, style: theme.textTheme.headlineMedium),
                  const SizedBox(height: 4),
                  Text('Plan things to do with your friends.',
                      textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 32),
                  if (_signUp) ...[
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
                      decoration: const InputDecoration(labelText: 'Display name (optional)', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextFormField(
                    controller: _email,
                    decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    validator: (v) => (v ?? '').contains('@') ? null : 'Enter your email',
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _password,
                    decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
                    obscureText: true,
                    onFieldSubmitted: (_) => _submit(),
                    validator: (v) => (v ?? '').length >= 8 ? null : 'At least 8 characters',
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: _busy
                          ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(_signUp ? 'Create account' : 'Sign in'),
                    ),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                              _signUp = !_signUp;
                              _error = null;
                            }),
                    child: Text(_signUp ? 'Already have an account? Sign in' : 'New here? Create an account'),
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
