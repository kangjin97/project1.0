import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/activities_repository.dart';
import '../../data/groups_repository.dart';
import '../../data/models.dart';
import '../../data/schedule_models.dart';
import '../../data/schedule_repository.dart';
import '../../widgets/dialogs.dart';
import 'schedule_widgets.dart';

enum _What { activity, event }

enum _When { timed, allDay, unscheduled }

/// Opens the editor to plan something. [groupId] and [activityId] preselect;
/// [day] presets the date. Returns the new entry's id when saved.
Future<String?> showEntryEditor(BuildContext context, {String? groupId, String? activityId, DateTime? day}) {
  return Navigator.of(context, rootNavigator: true).push<String>(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => EntryEditorPage(groupId: groupId, activityId: activityId, day: day),
  ));
}

/// Opens the editor to change when an existing entry happens. Returns true when saved.
Future<bool> showRescheduleEditor(BuildContext context, ScheduleEntry entry) async {
  final saved = await Navigator.of(context, rootNavigator: true).push<String>(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => EntryEditorPage(existing: entry),
  ));
  return saved != null;
}

class EntryEditorPage extends ConsumerStatefulWidget {
  const EntryEditorPage({super.key, this.groupId, this.activityId, this.day, this.existing});

  final String? groupId;
  final String? activityId;
  final DateTime? day;

  /// When set, only the timing is edited (reschedule).
  final ScheduleEntry? existing;

  @override
  ConsumerState<EntryEditorPage> createState() => _EntryEditorPageState();
}

class _EntryEditorPageState extends ConsumerState<EntryEditorPage> {
  final _me = Supabase.instance.client.auth.currentUser!.id;
  final _title = TextEditingController();

  late String? _groupId = widget.existing?.groupId ?? widget.groupId;
  late _What _what = widget.activityId != null || (widget.existing != null && !widget.existing!.isEvent)
      ? _What.activity
      : (widget.existing?.isEvent ?? false)
          ? _What.event
          : _What.activity;
  late String? _activityId = widget.activityId;
  late _When _when;
  late DateTime _date;
  late TimeOfDay _start;
  late TimeOfDay _end;
  late final Set<String> _people = {_me};
  bool _saving = false;

  bool get _rescheduling => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    final now = DateTime.now();
    _date = dateOnly(widget.day ?? now);
    _start = TimeOfDay(hour: (now.hour + 1).clamp(0, 22), minute: 0);
    _end = TimeOfDay(hour: (_start.hour + 2).clamp(0, 23), minute: 0);
    _when = _When.timed;
    if (e != null) {
      if (e.isUnscheduled) {
        _when = _When.unscheduled;
      } else if (e.allDay) {
        _when = _When.allDay;
        _date = e.date!;
      } else {
        _date = dateOnly(e.startAt!);
        _start = TimeOfDay.fromDateTime(e.startAt!);
        _end = TimeOfDay.fromDateTime(e.endAt!);
      }
    }
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  DateTime _at(DateTime day, TimeOfDay t) => DateTime(day.year, day.month, day.day, t.hour, t.minute);

  /// An end at or before the start means it runs past midnight.
  bool get _overnight => _end.hour * 60 + _end.minute <= _start.hour * 60 + _start.minute;

  EntryTiming get _timing => switch (_when) {
        _When.allDay => AllDayTiming(_date),
        _When.unscheduled => const UnscheduledTiming(),
        _When.timed => TimedTiming(_at(_date, _start), _at(_overnight ? addDays(_date, 1) : _date, _end)),
      };

  String? get _problem {
    if (_groupId == null) return 'Choose a group';
    if (_rescheduling) return null;
    if (_what == _What.activity && _activityId == null) return 'Choose an activity';
    if (_what == _What.event && _title.text.trim().isEmpty) return 'Name the event';
    if (_people.isEmpty) return 'Choose who’s going';
    return null;
  }

  Future<void> _save() async {
    final problem = _problem;
    if (problem != null) {
      showMessage(context, problem);
      return;
    }
    setState(() => _saving = true);
    final repo = ref.read(scheduleRepositoryProvider);
    try {
      Future<ScheduleResult> attempt(bool force) => _rescheduling
          ? repo.reschedule(widget.existing!.id, _timing, force: force)
          : repo.create(
              groupId: _groupId!,
              activityId: _what == _What.activity ? _activityId : null,
              title: _what == _What.event ? _title.text : null,
              timing: _timing,
              participantIds: _people.toList(),
              force: force,
            );

      var result = await attempt(false);
      if (!result.saved) {
        if (!mounted) return;
        final proceed = await confirmClashes(context, result.clashes);
        if (!proceed) {
          setState(() => _saving = false);
          return;
        }
        result = await attempt(true);
      }
      invalidateSchedule(ref);
      if (mounted) Navigator.pop(context, result.entryId ?? widget.existing?.id ?? '');
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const gap = SizedBox(height: 20);
    return Scaffold(
      appBar: AppBar(
        title: Text(_rescheduling ? 'Change time' : 'Add to schedule'),
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
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_rescheduling) ...[
                    Text(widget.existing!.displayTitle, style: theme.textTheme.titleLarge),
                    Text(widget.existing!.groupName, style: theme.textTheme.bodyMedium),
                    gap,
                  ] else ...[
                    if (widget.groupId == null) ...[_groupPicker(), gap],
                    if (_groupId != null) ...[_whatPicker(), gap],
                  ],
                  _whenPicker(),
                  if (!_rescheduling && _groupId != null) ...[gap, _peoplePicker()],
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> children) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          ...children,
        ],
      );

  Widget _groupPicker() {
    final groups = ref.watch(myGroupsProvider).value ?? const <Group>[];
    return _section('Group', [
      if (groups.isEmpty)
        const Text('Join or create a group first. Plans are made inside a group.')
      else
        DropdownButtonFormField<String>(
          initialValue: _groupId,
          decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Choose a group'),
          items: [for (final g in groups) DropdownMenuItem(value: g.id, child: Text(g.name))],
          onChanged: (v) => setState(() {
            _groupId = v;
            _activityId = null;
            _people
              ..clear()
              ..add(_me);
          }),
        ),
    ]);
  }

  Widget _whatPicker() {
    final activities = ref.watch(groupActivitiesProvider(_groupId!)).value ?? const <GroupActivity>[];
    return _section('What', [
      SegmentedButton<_What>(
        segments: const [
          ButtonSegment(value: _What.activity, icon: Icon(Icons.local_activity_outlined), label: Text('Activity')),
          ButtonSegment(value: _What.event, icon: Icon(Icons.lightbulb_outline), label: Text('Event')),
        ],
        selected: {_what},
        onSelectionChanged: (s) => setState(() {
          _what = s.first;
          if (_what == _What.activity && _when == _When.unscheduled) _when = _When.timed;
        }),
      ),
      const SizedBox(height: 12),
      if (_what == _What.activity)
        activities.isEmpty
            ? const Text('This group has no activities yet. Add one in the group’s Activities tab, or plan an event.')
            : DropdownButtonFormField<String>(
                initialValue: activities.any((a) => a.activityId == _activityId) ? _activityId : null,
                isExpanded: true,
                decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Choose an activity'),
                items: [
                  for (final ga in activities)
                    DropdownMenuItem(
                      value: ga.activityId,
                      child: Text(
                        ga.typeName == null ? ga.activity.name : '${ga.activity.name} · ${ga.typeName}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => _activityId = v),
              )
      else ...[
        TextField(
          controller: _title,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Event name',
            hintText: 'e.g. Eat some steak',
          ),
        ),
        const SizedBox(height: 4),
        Text('An idea without a specific activity yet. Anyone in the group can swap in an activity later.',
            style: Theme.of(context).textTheme.bodySmall),
      ],
    ]);
  }

  Widget _whenPicker() {
    final isEvent = _rescheduling ? widget.existing!.isEvent : _what == _What.event;
    final dateText = DateFormat('EEE, d MMM y').format(_date);
    return _section('When', [
      SegmentedButton<_When>(
        segments: [
          const ButtonSegment(value: _When.timed, label: Text('Time')),
          const ButtonSegment(value: _When.allDay, label: Text('All day')),
          if (isEvent) const ButtonSegment(value: _When.unscheduled, label: Text('No date yet')),
        ],
        selected: {_when},
        onSelectionChanged: (s) => setState(() => _when = s.first),
      ),
      const SizedBox(height: 12),
      if (_when != _When.unscheduled)
        OutlinedButton.icon(
          onPressed: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _date,
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            );
            if (picked != null) setState(() => _date = dateOnly(picked));
          },
          icon: const Icon(Icons.calendar_today_outlined),
          label: Align(alignment: Alignment.centerLeft, child: Text(dateText)),
        ),
      if (_when == _When.timed) ...[
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _timeButton('Starts', _start, (t) => _start = t)),
            const SizedBox(width: 8),
            Expanded(child: _timeButton('Ends', _end, (t) => _end = t)),
          ],
        ),
        if (_overnight)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Ends the next day.', style: Theme.of(context).textTheme.bodySmall),
          ),
      ],
      if (_when == _When.allDay)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('An all-day plan counts as a clash with anything else that day.',
              style: Theme.of(context).textTheme.bodySmall),
        ),
    ]);
  }

  Widget _timeButton(String label, TimeOfDay value, ValueChanged<TimeOfDay> set) => OutlinedButton(
        onPressed: () async {
          final picked = await showTimePicker(context: context, initialTime: value);
          if (picked != null) setState(() => set(picked));
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: [
              Text(label, style: Theme.of(context).textTheme.labelSmall),
              Text(value.format(context), style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ),
      );

  Widget _peoplePicker() {
    final members = ref.watch(membersProvider(_groupId!)).value ?? const <Member>[];
    return _section('Who’s going', [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final m in members)
            FilterChip(
              label: Text(m.profile.id == _me ? '${m.profile.label} (you)' : m.profile.label),
              selected: _people.contains(m.profile.id),
              onSelected: (on) => setState(() => on ? _people.add(m.profile.id) : _people.remove(m.profile.id)),
            ),
        ],
      ),
      const SizedBox(height: 4),
      Text('They’re added straight away. You’ll be warned if anyone already has plans.',
          style: Theme.of(context).textTheme.bodySmall),
    ]);
  }
}
