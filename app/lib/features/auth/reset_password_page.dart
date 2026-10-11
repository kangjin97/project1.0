import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../widgets/dialogs.dart';

/// Opened from a password-reset email. The link signs the user in briefly;
/// they choose a new password here.
class ResetPasswordPage extends StatefulWidget {
  const ResetPasswordPage({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  StreamSubscription<AuthState>? _sub;
  Timer? _timeout;
  bool _expired = false;
  bool _busy = false;

  SupabaseClient get _db => Supabase.instance.client;
  bool get _ready => _db.auth.currentSession != null;

  @override
  void initState() {
    super.initState();
    // The link's code is exchanged for a session as the app starts; wait for it.
    _sub = _db.auth.onAuthStateChange.listen((_) {
      if (mounted) setState(() {});
    });
    _timeout = Timer(const Duration(seconds: 10), () {
      if (mounted && !_ready) setState(() => _expired = true);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _timeout?.cancel();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await _db.auth.updateUser(UserAttributes(password: _password.text));
      if (!mounted) return;
      showMessage(context, 'Password changed');
      widget.onDone();
      context.go('/schedule');
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget body;
    if (_ready) {
      body = Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Choose a new password', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 24),
            TextFormField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'New password', border: OutlineInputBorder()),
              validator: (v) => (v ?? '').length >= 8 ? null : 'At least 8 characters',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _confirm,
              obscureText: true,
              onFieldSubmitted: (_) => _save(),
              decoration: const InputDecoration(labelText: 'Repeat new password', border: OutlineInputBorder()),
              validator: (v) => v == _password.text ? null : 'Doesn’t match',
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Save password')),
            ),
          ],
        ),
      );
    } else if (_expired) {
      body = Column(
        children: [
          Icon(Icons.link_off, size: 48, color: theme.colorScheme.outline),
          const SizedBox(height: 12),
          const Text('This reset link is invalid or has expired. Request a new one from the sign-in screen.',
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              widget.onDone();
              context.go('/auth');
            },
            child: const Text('Back to sign in'),
          ),
        ],
      );
    } else {
      body = const Center(child: CircularProgressIndicator());
    }
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 400), child: body),
        ),
      ),
    );
  }
}
