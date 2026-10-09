import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Stand-in for screens that come later in the build order.
class PlaceholderPage extends StatelessWidget {
  const PlaceholderPage({super.key, required this.title, required this.icon, required this.message});

  final String title;
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (MediaQuery.sizeOf(context).width < 720)
            IconButton(
              tooltip: 'Sign out',
              icon: const Icon(Icons.logout),
              onPressed: () => Supabase.instance.client.auth.signOut(),
            ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: theme.colorScheme.outline),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
            ],
          ),
        ),
      ),
    );
  }
}
