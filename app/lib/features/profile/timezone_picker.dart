import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/app_clock.dart';
import '../../data/schedule_repository.dart';
import '../../widgets/async_body.dart';
import '../../widgets/dialogs.dart';

/// Lets the user pick the time zone the app shows times in.
Future<void> showTimezonePicker(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (_, controller) => _TimezonePicker(controller: controller),
      ),
    );

class _TimezonePicker extends ConsumerStatefulWidget {
  const _TimezonePicker({required this.controller});

  final ScrollController controller;

  @override
  ConsumerState<_TimezonePicker> createState() => _TimezonePickerState();
}

class _TimezonePickerState extends ConsumerState<_TimezonePicker> {
  String _query = '';
  bool _saving = false;

  Future<void> _choose(String name) async {
    setState(() => _saving = true);
    try {
      await ref.read(timezoneProvider.notifier).change(name);
      invalidateSchedule(ref);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showError(context, e);
      }
    }
  }

  /// Matches city, region, zone id, or an offset typed as "+8", "8:00", "-3", "utc+5:30".
  bool _matches(TimezoneOption z, String q) {
    if (q.isEmpty) return true;
    final text = '${z.city} ${z.region} ${z.name}'.toLowerCase();
    if (text.contains(q)) return true;
    final offset = formatOffset(z.offsetMinutes).toLowerCase(); // utc+08:00
    final compact = q.replaceAll('utc', '').replaceAll('gmt', '').replaceAll(' ', '').replaceAll('−', '-');
    final m = RegExp(r'^([+-])?(\d{1,2})(?::?(\d{2}))?$').firstMatch(compact);
    if (m == null) return offset.contains(q);
    final sign = m.group(1) == '-' ? -1 : 1;
    final minutes = sign * (int.parse(m.group(2)!) * 60 + int.parse(m.group(3) ?? '0'));
    return z.offsetMinutes == minutes;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = ref.watch(timezoneProvider);
    final device = AppClock.deviceZone;
    final q = _query.trim().toLowerCase();

    return AsyncBody(
      value: ref.watch(timezoneOptionsProvider),
      builder: (all) {
        final list = all.where((z) => _matches(z, q)).toList();
        final deviceOption = all.where((z) => z.name == device).firstOrNull;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Time zone', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(
                    'Plan times, calendar days and all-day clash checks use this zone.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  SearchBar(
                    autoFocus: false,
                    hintText: 'Search city, region or offset (e.g. +8)',
                    leading: const Icon(Icons.search),
                    elevation: const WidgetStatePropertyAll(0),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ],
              ),
            ),
            if (_saving) const LinearProgressIndicator(),
            Expanded(
              child: ListView(
                controller: widget.controller,
                children: [
                  if (q.isEmpty && deviceOption != null && deviceOption.name != current) ...[
                    ListTile(
                      leading: const Icon(Icons.my_location),
                      title: Text('Use this device’s time zone · ${deviceOption.city}'),
                      subtitle: Text('${deviceOption.region} · ${formatOffset(deviceOption.offsetMinutes)}'),
                      onTap: _saving ? null : () => _choose(deviceOption.name),
                    ),
                    const Divider(),
                  ],
                  if (list.isEmpty)
                    const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No time zones match.'))),
                  for (final z in list)
                    ListTile(
                      selected: z.name == current,
                      leading: z.name == current ? const Icon(Icons.check) : const SizedBox(width: 24),
                      title: Text(z.city),
                      subtitle: Text(z.region),
                      trailing: Text(formatOffset(z.offsetMinutes), style: theme.textTheme.labelLarge),
                      onTap: _saving || z.name == current ? null : () => _choose(z.name),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
