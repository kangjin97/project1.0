import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/activities_repository.dart';
import '../../data/activity_sheet.dart';
import '../../data/export/save_file.dart';
import '../../data/groups_repository.dart';
import '../../data/places_repository.dart';
import '../../widgets/dialogs.dart';

const _xlsxType = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

/// Import activities from an .xlsx or .csv into My activities (#111). Returns
/// how many were imported, or null when cancelled.
Future<int?> showActivityImport(BuildContext context) => Navigator.of(
  context,
  rootNavigator: true,
).push<int>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const ImportActivitiesPage()));

/// The blank spreadsheet to fill in.
Future<void> downloadActivityTemplate() => saveFile(
  Uint8List.fromList(activitiesToExcel(const [], withExample: true)),
  name: 'EasyPlan activities template.xlsx',
  mimeType: _xlsxType,
);

/// A row in the preview, with what the person chose for it.
class _Entry {
  _Entry(this.row, {required this.duplicate}) : selected = row.ok && !duplicate;

  final ImportRow row;

  /// Can also turn true once its location is matched to a place you already have.
  bool duplicate;
  bool selected;

  /// The person ticked or unticked it, so matching mustn't change it.
  bool touched = false;

  /// The Google place found for the row's location (when the sheet had none).
  String? matchedPlaceId;
  String? matchedLabel;
  bool matching = false;
  bool useMatch = true;

  bool get needsMatch => row.ok && row.location != null && row.placeId == null;
}

class ImportActivitiesPage extends ConsumerStatefulWidget {
  const ImportActivitiesPage({super.key});

  @override
  ConsumerState<ImportActivitiesPage> createState() => _ImportActivitiesPageState();
}

class _ImportActivitiesPageState extends ConsumerState<ImportActivitiesPage> {
  String? _fileName;
  List<_Entry>? _entries;
  String? _error;
  bool _busy = false;
  bool _matching = false;
  String? _matchNote;
  DuplicateCheck? _duplicates;

  /// Bumped for every file chosen, so matching still running for an earlier
  /// file stops and leaves the new one alone.
  int _run = 0;

  /// Place searches running at once while matching.
  static const _parallel = 3;

  Future<void> _pick() async {
    final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['xlsx', 'csv']);
    if (file == null) return;
    final run = ++_run;
    setState(() {
      _busy = true;
      _matching = false;
      _error = null;
      _entries = null;
      _matchNote = null;
    });
    try {
      final sheet = parseActivitySheet(await file.readAsBytes(), file.name);
      if (sheet.error != null) {
        setState(() => _error = sheet.error);
        return;
      }
      // An activity already in the list, or earlier in the same sheet, starts unticked.
      final duplicates = DuplicateCheck(await ref.read(myActivitiesProvider.future));
      final entries = <_Entry>[];
      for (final row in sheet.rows) {
        entries.add(
          _Entry(row, duplicate: duplicates.contains(row.name, location: row.location, placeId: row.placeId)),
        );
        if (row.ok) duplicates.add(row.name, location: row.location, placeId: row.placeId);
      }
      if (run != _run || !mounted) return;
      setState(() {
        _fileName = file.name;
        _entries = entries;
        _duplicates = duplicates;
      });
      unawaited(_matchPlaces(run));
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Matches each location to a Google place, a few at a time. Each search
  /// counts against the daily place-search quota; when it's used up the
  /// rest keep their text. Rows already known to be duplicates go last, so
  /// the quota goes to new ones first.
  Future<void> _matchPlaces(int run) async {
    final queue = [
      ...?_entries?.where((e) => e.needsMatch && !e.duplicate),
      ...?_entries?.where((e) => e.needsMatch && e.duplicate),
    ];
    if (queue.isEmpty) return;
    setState(() => _matching = true);
    final places = ref.read(placesRepositoryProvider);
    var stopped = false;
    bool current() => mounted && run == _run;

    Future<void> worker() async {
      while (queue.isNotEmpty && !stopped && current()) {
        final entry = queue.removeAt(0);
        setState(() => entry.matching = true);
        try {
          final found = await places.suggest(entry.row.location!);
          if (found.isNotEmpty && current()) _matched(entry, found.first);
        } on PlaceSearchException catch (e) {
          stopped = true;
          if (current()) _matchNote = '${e.message} Locations not matched yet keep their text.';
        } catch (_) {
          // Leave this one as text.
        }
        if (current()) setState(() => entry.matching = false);
      }
    }

    await Future.wait([for (var i = 0; i < _parallel; i++) worker()]);
    if (current()) setState(() => _matching = false);
  }

  /// Keeps [place] for [entry], and unticks it if you already have that
  /// place under the same name (unless you've ticked or unticked it yourself).
  void _matched(_Entry entry, PlaceSuggestion place) {
    entry.matchedPlaceId = place.placeId;
    entry.matchedLabel = place.label;
    final duplicates = _duplicates!;
    if (!entry.duplicate && duplicates.hasPlace(entry.row.name, place.placeId)) {
      entry.duplicate = true;
      if (!entry.touched) entry.selected = false;
    }
    duplicates.add(entry.row.name, location: place.label, placeId: place.placeId);
  }

  Future<void> _import() async {
    final chosen = [...?_entries?.where((e) => e.selected)];
    if (chosen.isEmpty) return;
    setState(() => _busy = true);
    try {
      final repo = ref.read(activitiesRepositoryProvider);
      final labelIds = await repo.labelIdsFor({for (final e in chosen) ?e.row.label});
      final inputs = [
        for (final e in chosen)
          () {
            final match = e.useMatch && e.matchedPlaceId != null;
            return ActivityInput(
              name: e.row.name,
              description: e.row.description,
              location: match ? e.matchedLabel : e.row.location,
              placeId: match ? e.matchedPlaceId : e.row.placeId,
              priceMin: e.row.priceMin,
              priceMax: e.row.priceMax,
              currency: e.row.currency,
              url: e.row.url,
              personalTypeId: e.row.label == null ? null : labelIds[e.row.label!.trim().toLowerCase()],
              setLabel: e.row.label != null,
            );
          }(),
      ];
      final count = await repo.createMany(inputs);
      ref.invalidate(myActivitiesProvider);
      invalidateLabels(ref);
      if (mounted) Navigator.pop(context, count);
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
    final entries = _entries;
    final chosen = entries?.where((e) => e.selected).length ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Import activities'),
        actions: [
          TextButton.icon(
            onPressed: _busy ? null : downloadActivityTemplate,
            icon: const Icon(Icons.download),
            label: const Text('Template'),
          ),
        ],
      ),
      bottomNavigationBar: entries == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton(
                  onPressed: _busy || _matching || chosen == 0 ? null : _import,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      _matching ? 'Matching places…' : 'Import $chosen ${chosen == 1 ? 'activity' : 'activities'}',
                    ),
                  ),
                ),
              ),
            ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          // Open until a file is picked, then folded away but still at hand.
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
              key: ValueKey(entries == null),
              initiallyExpanded: entries == null,
              leading: const Icon(Icons.lightbulb_outline),
              title: const Text('How importing works'),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [_HowToImport(onTemplate: _busy ? null : downloadActivityTemplate)],
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _pick,
              icon: const Icon(Icons.upload_file),
              label: Text(_fileName == null ? 'Choose a file' : 'Choose another file'),
            ),
          ),
          if (_busy && entries == null) const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ),
          if (entries != null) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Flexible(child: Text(_summary(entries), style: theme.textTheme.titleSmall)),
                const Tooltip(
                  message:
                      'Ticked rows are imported. Rows in red have a problem: fix them in the file and choose it again. '
                      'Rows already in your list start unticked; tick them to add them anyway.',
                  triggerMode: TooltipTriggerMode.tap,
                  showDuration: Duration(seconds: 8),
                  child: Padding(padding: EdgeInsets.all(6), child: Icon(Icons.info_outline, size: 18)),
                ),
              ],
            ),
            if (_matching)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 12),
                    Text(
                      'Matching places on Google Maps: '
                      '${entries.where((e) => e.needsMatch && !e.matching && (e.matchedPlaceId != null)).length} found so far',
                    ),
                  ],
                ),
              ),
            if (_matchNote != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_matchNote!, style: theme.textTheme.bodySmall),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton(
                  onPressed: () => setState(() {
                    for (final e in entries) {
                      e.selected = e.row.ok;
                      e.touched = true;
                    }
                  }),
                  child: const Text('Select all'),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    for (final e in entries) {
                      e.selected = false;
                      e.touched = true;
                    }
                  }),
                  child: const Text('Select none'),
                ),
              ],
            ),
            for (final e in entries) _EntryTile(entry: e, onChanged: () => setState(() {})),
          ],
        ],
      ),
    );
  }

  String _summary(List<_Entry> entries) {
    final problems = entries.where((e) => !e.row.ok).length;
    final dupes = entries.where((e) => e.duplicate).length;
    return [
      '${entries.length} in $_fileName',
      if (problems > 0) '$problems with problems',
      if (dupes > 0) '$dupes already in your list',
    ].join(' · ');
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry, required this.onChanged});

  final _Entry entry;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final row = entry.row;
    final price = row.priceLabel;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: entry.selected,
              onChanged: row.ok
                  ? (v) {
                      entry.selected = v ?? false;
                      entry.touched = true;
                      onChanged();
                    }
                  : null,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 10),
                  Text(row.name.isEmpty ? '(no name) · row ${row.line}' : row.name, style: theme.textTheme.titleSmall),
                  if (row.location != null) ...[
                    const SizedBox(height: 2),
                    if (entry.matching)
                      Text('Finding ${row.location} on Google Maps…', style: muted)
                    else if (entry.matchedPlaceId != null && entry.useMatch)
                      Row(
                        children: [
                          Tooltip(
                            message: 'Found on Google Maps from "${row.location}". Tap × if it’s the wrong place.',
                            triggerMode: TooltipTriggerMode.tap,
                            child: Icon(Icons.place, size: 14, color: theme.colorScheme.primary),
                          ),
                          const SizedBox(width: 4),
                          Expanded(child: Text(entry.matchedLabel!, style: muted)),
                          IconButton(
                            tooltip: 'Wrong place: keep the text instead',
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.close, size: 16),
                            onPressed: () {
                              entry.useMatch = false;
                              onChanged();
                            },
                          ),
                        ],
                      )
                    else
                      Text(
                        row.placeId != null ? '${row.location} · Google place from the sheet' : row.location!,
                        style: muted,
                      ),
                  ],
                  if (price != null || row.label != null)
                    Text([?price, if (row.label != null) 'Label: ${row.label}'].join(' · '), style: muted),
                  if (entry.duplicate)
                    Tooltip(
                      message:
                          'You already have an activity with this name and location (or it’s earlier in this file), '
                          'so it starts unticked. Tick it to add it anyway.',
                      triggerMode: TooltipTriggerMode.tap,
                      child: Text('Already in your list ⓘ', style: muted?.copyWith(color: theme.colorScheme.tertiary)),
                    ),
                  for (final p in row.problems)
                    Text('Row ${row.line}: $p', style: muted?.copyWith(color: theme.colorScheme.error)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The guide at the top of the import page.
class _HowToImport extends StatelessWidget {
  const _HowToImport({required this.onTemplate});

  final VoidCallback? onTemplate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    Widget step(int n, String title, String detail) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(radius: 11, child: Text('$n', style: const TextStyle(fontSize: 12))),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                Text(detail, style: small),
              ],
            ),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        step(
          1,
          'Make a sheet',
          'In Excel, Google Sheets or a scraped CSV: one activity per row, column names in the first row.',
        ),
        step(2, 'Choose the file', 'An .xlsx or .csv, up to $maxImportRows activities. Nothing is saved yet.'),
        step(
          3,
          'Check the preview',
          'Locations are matched to Google Maps places. Rows with problems are shown in red; '
              'ones you already have start unticked.',
        ),
        step(4, 'Import', 'The ticked rows become your own private activities, ready to edit or share.'),
        const SizedBox(height: 4),
        Text('Columns', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        // Like the sheet itself: header row, then an example row.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowHeight: 32,
            dataRowMinHeight: 28,
            dataRowMaxHeight: 32,
            horizontalMargin: 8,
            columnSpacing: 16,
            border: TableBorder.all(color: theme.colorScheme.outlineVariant),
            columns: const [
              DataColumn(label: Text('Name *')),
              DataColumn(label: Text('Location')),
              DataColumn(label: Text('Price')),
              DataColumn(label: Text('Link')),
              DataColumn(label: Text('Label')),
            ],
            rows: const [
              DataRow(
                cells: [
                  DataCell(Text('Bishan Pickleball')),
                  DataCell(Text('Bishan Sports Hall')),
                  DataCell(Text(r'$10-15')),
                  DataCell(Text('activesg.gov.sg')),
                  DataCell(Text('Pickleball')),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Only Name is required. Other names work too (Title, Address, Website, Category, "Court name"…), as do '
          'Description, Currency (SGD if empty) and separate Price from / Price to columns. Prices can be "15", '
          r'"$10-15" or "free". New labels are created for you.',
          style: small,
        ),
        const SizedBox(height: 4),
        Text('Got a file from a friend’s “Select to export”? Import it as it is.', style: small),
        const SizedBox(height: 4),
        Text(
          'The template has an example row to copy. Change or delete it; left as it is, it’s skipped on import.',
          style: small,
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onTemplate,
          icon: const Icon(Icons.download),
          label: const Text('Download the template'),
        ),
      ],
    );
  }
}
