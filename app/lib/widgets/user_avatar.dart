import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/profile_repository.dart';

/// A person's picture, or the first letter of [label] when they have none.
class UserAvatar extends ConsumerWidget {
  const UserAvatar({super.key, required this.label, this.avatarPath, this.radius = 20});

  final String label;
  final String? avatarPath;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final initial = CircleAvatar(
      radius: radius,
      child: Text(
        label.isEmpty ? '?' : label.characters.first.toUpperCase(),
        style: TextStyle(fontSize: radius * 0.8),
      ),
    );
    final path = avatarPath;
    if (path == null) return initial;
    return ref.watch(avatarUrlProvider(path)).maybeWhen(
          data: (url) => CircleAvatar(radius: radius, backgroundImage: NetworkImage(url)),
          orElse: () => initial,
        );
  }
}
