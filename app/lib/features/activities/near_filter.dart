import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/geo.dart';
import '../../data/models.dart';
import '../../data/places_repository.dart';
import 'place_field.dart';

/// The "Near…" filter chip (#94): shows the current filter and opens the sheet
/// to change or clear it.
class NearFilterChip extends StatelessWidget {
  const NearFilterChip({super.key, required this.value, required this.onChanged});

  final NearFilter? value;
  final ValueChanged<NearFilter?> onChanged;

  @override
  Widget build(BuildContext context) {
    final v = value;
    return FilterChip(
      avatar: const Icon(Icons.near_me_outlined, size: 16),
      label: Text(v == null ? 'Near…' : 'Within ${formatDistance(v.km)} of ${v.label}'),
      selected: v != null,
      onSelected: (_) async {
        final result = await showNearSheet(context, v);
        if (result != null) onChanged(result.filter);
      },
    );
  }
}

/// Asks where and how far. Null when dismissed; a record with a null filter
/// when the person clears it.
Future<({NearFilter? filter})?> showNearSheet(BuildContext context, NearFilter? current) =>
    showModalBottomSheet<({NearFilter? filter})>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _NearSheet(current: current),
    );

class _NearSheet extends ConsumerStatefulWidget {
  const _NearSheet({required this.current});

  final NearFilter? current;

  @override
  ConsumerState<_NearSheet> createState() => _NearSheetState();
}

class _NearSheetState extends ConsumerState<_NearSheet> {
  final _place = TextEditingController();
  String? _placeId;
  late GeoPoint? _point = widget.current?.point;
  late String? _label = widget.current?.label;
  late double _km = widget.current?.km ?? 5;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _place.dispose();
    super.dispose();
  }

  Future<void> _useMyLocation() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final here = await ref.read(placesRepositoryProvider).currentPosition();
      setState(() {
        _point = here;
        _label = 'your location';
      });
    } on LocationException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Couldn’t get your location. Search for a place instead.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _placePicked(String? placeId) async {
    setState(() => _placeId = placeId);
    if (placeId == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final found = await ref.read(placesRepositoryProvider).coordinates([placeId]);
    if (!mounted) return;
    final at = found.byPlace[placeId];
    setState(() {
      _busy = false;
      if (at == null) {
        _error = found.error ?? 'Couldn’t find where that place is. Try another.';
      } else {
        _point = at;
        // "Orchard MRT, Singapore" → "Orchard MRT".
        _label = _place.text.split(',').first.trim();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Activities near…', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('Straight-line distance from a place. Only activities with a place picked from Google Maps can be measured.',
                style: theme.textTheme.bodySmall),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _busy ? null : _useMyLocation,
              icon: const Icon(Icons.my_location),
              label: const Text('Use my location'),
            ),
            const SizedBox(height: 12),
            PlaceField(
              controller: _place,
              placeId: _placeId,
              onPlaceChanged: _placePicked,
              label: 'Or search a place',
              hint: 'e.g. a station, a mall or a neighbourhood',
            ),
            const SizedBox(height: 12),
            if (_busy) const LinearProgressIndicator(),
            if (_point != null && !_busy)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.place, color: theme.colorScheme.primary),
                title: Text('From $_label'),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ),
            Text('Within', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final km in NearFilter.distances)
                  ChoiceChip(
                    label: Text(formatDistance(km)),
                    selected: _km == km,
                    onSelected: (_) => setState(() => _km = km),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                if (widget.current != null)
                  TextButton(
                    onPressed: () => Navigator.pop(context, (filter: null)),
                    child: const Text('Clear'),
                  ),
                const Spacer(),
                FilledButton(
                  onPressed: _point == null || _busy
                      ? null
                      : () => Navigator.pop(context, (filter: NearFilter(point: _point!, label: _label!, km: _km))),
                  child: const Text('Show nearby'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Under a filtered list: says what the "Near…" filter couldn't measure, and
/// opens those activities so a place can be picked for them.
class NearNote extends StatelessWidget {
  const NearNote({super.key, required this.coordinates, required this.unmeasured});

  final AsyncValue<PlaceCoordinates> coordinates;
  final List<Activity> unmeasured;

  @override
  Widget build(BuildContext context) {
    if (coordinates.isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: [
          SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 12),
          Text('Finding distances…'),
        ]),
      );
    }
    final error = coordinates.value?.error ?? (coordinates.hasError ? 'Distances are unavailable right now.' : null);
    if (unmeasured.isEmpty && error == null) return const SizedBox.shrink();
    final n = unmeasured.length;
    return ListTile(
      leading: const Icon(Icons.location_off_outlined),
      title: Text(n == 0 ? error! : '$n ${n == 1 ? 'activity has' : 'activities have'} no map location'),
      subtitle: n == 0
          ? null
          : Text(error ?? 'Edit them and pick the place from the Google suggestions to include them.'),
      onTap: n == 0
          ? null
          : () => showModalBottomSheet<void>(
                context: context,
                useRootNavigator: true,
                showDragHandle: true,
                builder: (sheet) => ListView(
                  shrinkWrap: true,
                  children: [
                    const ListTile(title: Text('No map location'), subtitle: Text('Open one, tap Edit and pick its place.')),
                    for (final a in unmeasured)
                      ListTile(
                        leading: const Icon(Icons.local_activity_outlined),
                        title: Text(a.name),
                        subtitle: a.location == null ? const Text('No location') : Text(a.location!),
                        onTap: () {
                          Navigator.pop(sheet);
                          context.push('/activities/${a.id}');
                        },
                      ),
                  ],
                ),
              ),
    );
  }
}
