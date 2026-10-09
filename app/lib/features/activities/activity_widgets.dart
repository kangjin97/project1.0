import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/activities_repository.dart';
import '../../data/models.dart';

/// A photo from the private bucket, loaded through a signed URL.
class ActivityPhotoImage extends ConsumerWidget {
  const ActivityPhotoImage({super.key, required this.storagePath, this.fit = BoxFit.cover});

  final String storagePath;
  final BoxFit fit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Center(child: Icon(Icons.image_outlined, color: scheme.outline)),
    );
    return ref.watch(photoUrlProvider(storagePath)).maybeWhen(
          data: (url) => Image.network(url, fit: fit, errorBuilder: (_, _, _) => placeholder),
          orElse: () => placeholder,
        );
  }
}

/// List card for an activity: thumbnail, name, location, price and optional type.
class ActivityCard extends StatelessWidget {
  const ActivityCard({super.key, required this.activity, this.typeName, this.footer, this.onTap, this.trailing});

  final Activity activity;
  final String? typeName;
  final String? footer;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final price = activity.priceLabel;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox.square(
                  dimension: 64,
                  child: activity.photos.isNotEmpty
                      ? ActivityPhotoImage(storagePath: activity.photos.first.storagePath)
                      : ColoredBox(
                          color: theme.colorScheme.primaryContainer,
                          child: Center(
                            child: Text(
                              activity.name.characters.first.toUpperCase(),
                              style: theme.textTheme.titleLarge
                                  ?.copyWith(color: theme.colorScheme.onPrimaryContainer),
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(activity.name, style: theme.textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (activity.location != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Row(
                          children: [
                            Icon(Icons.place_outlined, size: 14, color: muted?.color),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(activity.location!, style: muted, maxLines: 1, overflow: TextOverflow.ellipsis),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (typeName != null) _Pill(text: typeName!, color: theme.colorScheme.secondaryContainer),
                        if (price != null) _Pill(text: price, color: theme.colorScheme.tertiaryContainer),
                        if (footer != null) Text(footer!, style: muted),
                      ],
                    ),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(999)),
        child: Text(text, style: Theme.of(context).textTheme.labelSmall),
      );
}
