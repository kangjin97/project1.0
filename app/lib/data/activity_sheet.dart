import 'dart:convert';

import 'package:excel/excel.dart';

import 'models.dart';

/// Activities in a spreadsheet (#111): the one layout used to import them
/// (from .xlsx or .csv) and to export selected ones, so an export can be
/// imported by someone else as it is.

enum SheetColumn {
  name('Name', ['name', 'title', 'activity', 'activity name']),
  description('Description', ['description', 'details', 'notes', 'note']),
  location('Location', ['location', 'address', 'place', 'venue', 'where']),
  placeId('Google place ID', ['google place id', 'place id', 'placeid', 'google place']),
  priceFrom('Price from', ['price from', 'price min', 'min price', 'from', 'price']),
  priceTo('Price to', ['price to', 'price max', 'max price', 'to']),
  currency('Currency', ['currency']),
  link('Link', ['link', 'url', 'website', 'web']),
  label('Label', ['label', 'type', 'category', 'tag']);

  const SheetColumn(this.header, this.aliases);

  final String header;
  final List<String> aliases;
}

/// How many rows one import takes.
const maxImportRows = 300;

/// The example row under the template's header, for people to copy. Left
/// exactly as it is, an import skips it; changed in any way, it's a real row.
const templateExample = {
  SheetColumn.name: 'Bishan Pickleball',
  SheetColumn.description: 'Indoor courts. Book on ActiveSG, up to 2 weeks ahead.',
  SheetColumn.location: 'Bishan Sports Hall',
  SheetColumn.priceFrom: '10',
  SheetColumn.priceTo: '15',
  SheetColumn.currency: 'SGD',
  SheetColumn.link: 'https://www.activesg.gov.sg',
  SheetColumn.label: 'Pickleball',
};

/// One activity read from a sheet, with what's wrong with it, if anything.
class ImportRow {
  ImportRow({required this.line});

  /// The row number in the sheet (1 = the first row), for messages.
  final int line;
  String name = '';
  String? description;
  String? location;
  String? placeId;
  double? priceMin;
  double? priceMax;
  String currency = 'SGD';
  String? url;
  String? label;
  final List<String> problems = [];

  bool get ok => problems.isEmpty;

  /// "SGD 10–15", "Free"…, worded like the activity list.
  String? get priceLabel => formatPriceRange(priceMin, priceMax, currency);
}

/// Spots activities the person already has (or that came earlier in the same
/// sheet): the same name with the same location text, or with the same Google
/// place. The place matters because an imported location is saved as Google's
/// text ("Bishan Sports Hall, Bishan Street 14, Singapore"), not the sheet's
/// ("Bishan Sports Hall"), so a second import of one sheet only matches on it.
class DuplicateCheck {
  DuplicateCheck(Iterable<Activity> existing) {
    for (final a in existing) {
      add(a.name, location: a.location, placeId: a.placeId);
    }
  }

  final _seen = <String>{};

  static Iterable<String> _keys(String name, String? location, String? placeId) sync* {
    final n = name.trim().toLowerCase();
    yield '$n|text|${(location ?? '').trim().toLowerCase()}';
    if (placeId != null) yield '$n|place|$placeId';
  }

  bool contains(String name, {String? location, String? placeId}) =>
      _keys(name, location, placeId).any(_seen.contains);

  /// Only the place: for a row whose location was matched after it was read.
  bool hasPlace(String name, String placeId) => _seen.contains('${name.trim().toLowerCase()}|place|$placeId');

  void add(String name, {String? location, String? placeId}) => _seen.addAll(_keys(name, location, placeId));
}

/// A whole sheet: its rows, or why it couldn't be read.
class ParsedSheet {
  ParsedSheet(this.rows, [this.error]);

  final List<ImportRow> rows;
  final String? error;
}

/// Reads an .xlsx or .csv ([fileName] decides which). The header row is
/// found by its "Name" column (within the first 10 rows); other columns are
/// matched by name, so extra columns and other orders are fine.
ParsedSheet parseActivitySheet(List<int> bytes, String fileName) {
  final List<List<String>> table;
  try {
    table = fileName.toLowerCase().endsWith('.csv') ? _csvTable(bytes) : _xlsxTable(bytes);
  } catch (_) {
    return ParsedSheet(const [], 'Couldn’t read that file. Use an .xlsx or .csv file.');
  }

  int? headerRow;
  final columns = <SheetColumn, int>{};
  for (var r = 0; r < table.length && r < 10 && headerRow == null; r++) {
    final found = <SheetColumn, int>{};
    for (var c = 0; c < table[r].length; c++) {
      final h = _normalise(table[r][c]);
      for (final col in SheetColumn.values) {
        if (!found.containsKey(col) && col.aliases.contains(h)) found[col] = c;
      }
    }
    // Scraped lists often say "Court name" or "Venue name".
    if (!found.containsKey(SheetColumn.name)) {
      final c = table[r].indexWhere((h) => _normalise(h).endsWith(' name'));
      if (c >= 0) found[SheetColumn.name] = c;
    }
    if (found.containsKey(SheetColumn.name)) {
      headerRow = r;
      columns.addAll(found);
    }
  }
  if (headerRow == null) {
    return ParsedSheet(const [], 'No "Name" column found. Use the template, or name the first row’s columns like it.');
  }

  final rows = <ImportRow>[];
  var onlyExample = false;
  for (var r = headerRow + 1; r < table.length; r++) {
    String? cell(SheetColumn col) {
      final i = columns[col];
      if (i == null || i >= table[r].length) return null;
      final v = table[r][i].trim();
      return v.isEmpty ? null : v;
    }

    if (SheetColumn.values.every((c) => cell(c) == null)) continue; // blank row
    if (SheetColumn.values.every((c) => cell(c) == templateExample[c])) {
      onlyExample = true; // the template's untouched example
      continue;
    }
    rows.add(_row(r + 1, cell, priceIsRange: !columns.containsKey(SheetColumn.priceTo)));
  }
  if (rows.isEmpty) {
    return ParsedSheet(
      const [],
      onlyExample
          ? 'That sheet only has the template’s example row. Add your activities under it (or change it), then choose the file again.'
          : 'That sheet has no activities under its header row.',
    );
  }
  if (rows.length > maxImportRows) {
    return ParsedSheet(const [], 'That sheet has ${rows.length} activities; import at most $maxImportRows at a time.');
  }
  return ParsedSheet(rows);
}

ImportRow _row(int line, String? Function(SheetColumn) cell, {required bool priceIsRange}) {
  final row = ImportRow(line: line);
  row.name = cell(SheetColumn.name) ?? '';
  if (row.name.isEmpty) row.problems.add('No name');
  if (row.name.length > 120) row.problems.add('Name is longer than 120 characters');
  row.description = cell(SheetColumn.description);
  row.location = cell(SheetColumn.location);

  final placeId = cell(SheetColumn.placeId);
  if (placeId != null) {
    if (!RegExp(r'^[A-Za-z0-9_-]{10,300}$').hasMatch(placeId)) {
      row.problems.add('"$placeId" isn’t a Google place ID');
    } else if (row.location == null) {
      row.problems.add('A Google place ID needs a location');
    } else {
      row.placeId = placeId;
    }
  }

  // A single "Price" column may hold a range ("10-20") or one amount.
  final from = cell(SheetColumn.priceFrom), to = cell(SheetColumn.priceTo);
  final (lo, hi) = priceIsRange && from != null ? parsePriceRange(from) : (parsePrice(from), parsePrice(to));
  if ((from != null && lo == null && !(priceIsRange && hi != null)) || (to != null && hi == null)) {
    row.problems.add('Price isn’t a number');
  } else if ((lo ?? 0) < 0 || (hi ?? 0) < 0) {
    row.problems.add('Price can’t be negative');
  } else if (lo != null && hi != null && hi < lo) {
    row.priceMin = hi;
    row.priceMax = lo;
  } else {
    row.priceMin = lo;
    row.priceMax = hi;
  }

  final currency = cell(SheetColumn.currency)?.toUpperCase();
  if (currency != null) {
    if (supportedCurrencies.contains(currency)) {
      row.currency = currency;
    } else {
      row.problems.add('Currency must be one of ${supportedCurrencies.join(', ')}');
    }
  }

  final link = cell(SheetColumn.link);
  if (link != null) {
    final withScheme = RegExp(r'^https?://', caseSensitive: false).hasMatch(link) ? link : 'https://$link';
    final uri = Uri.tryParse(withScheme);
    if (link.contains(' ') || uri == null || !uri.host.contains('.')) {
      row.problems.add('Link isn’t a web address');
    } else {
      row.url = withScheme;
    }
  }

  final label = cell(SheetColumn.label);
  if (label != null) {
    if (label.length > 40) {
      row.problems.add('Label is longer than 40 characters');
    } else {
      row.label = label;
    }
  }
  return row;
}

/// "12", "$12.50", "SGD 1,200", "free" → a number; null when empty or not a price.
double? parsePrice(String? text) {
  if (text == null || text.trim().isEmpty) return null;
  final t = text.trim().toLowerCase();
  if (t == 'free' || t == '-') return 0;
  final cleaned = t.replaceAll(RegExp(r'[^0-9.\-]'), '');
  if (cleaned.isEmpty || cleaned == '-' || cleaned == '.') return null;
  return double.tryParse(cleaned);
}

/// One "Price" cell: "10-20", "10 – 20", "$15", "free".
(double?, double?) parsePriceRange(String text) {
  final parts = text.split(RegExp(r'\s*(?:–|—|to|(?<=\d)\s*-\s*(?=\d|\$))\s*'));
  if (parts.length == 2) return (parsePrice(parts[0]), parsePrice(parts[1]));
  final one = parsePrice(text);
  return (one, one);
}

String _normalise(String header) => header.trim().toLowerCase().replaceAll(RegExp(r'[_\s]+'), ' ');

List<List<String>> _xlsxTable(List<int> bytes) {
  final book = Excel.decodeBytes(bytes);
  // An EasyPlan export or template names its sheet "Activities"; otherwise the first one with data.
  final sheet = book.tables['Activities'] ??
      book.tables.values.firstWhere((s) => s.maxRows > 0, orElse: () => book.tables.values.first);
  return [
    for (final row in sheet.rows)
      [
        for (final c in row)
          switch (c?.value) {
            null => '',
            DoubleCellValue(:final value) => value == value.roundToDouble() ? value.toInt().toString() : value.toString(),
            final v => v.toString(),
          },
      ],
  ];
}

/// RFC 4180 CSV: quoted fields, "" inside quotes, commas or semicolons
/// (Excel in some regions saves with semicolons), any line ending, a BOM.
List<List<String>> _csvTable(List<int> bytes) {
  var text = utf8.decode(bytes, allowMalformed: true);
  if (text.startsWith('﻿')) text = text.substring(1);
  final firstLine = text.split(RegExp(r'\r?\n')).first;
  final sep = ';'.allMatches(firstLine).length > ','.allMatches(firstLine).length ? ';' : ',';
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var quoted = false;
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (quoted) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        field.write(ch);
      }
    } else if (ch == '"') {
      quoted = true;
    } else if (ch == sep) {
      row.add(field.toString());
      field.clear();
    } else if (ch == '\n' || ch == '\r') {
      if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      row.add(field.toString());
      field.clear();
      rows.add(row);
      row = <String>[];
    } else {
      field.write(ch);
    }
  }
  if (field.isNotEmpty || row.isNotEmpty) {
    row.add(field.toString());
    rows.add(row);
  }
  return rows;
}

/// [activities] as an .xlsx in the import layout (an "Activities" sheet), plus
/// a "How to fill" sheet. The template is none, [withExample].
List<int> activitiesToExcel(List<Activity> activities, {bool withExample = false}) {
  final excel = Excel.createExcel();
  final defaultSheet = excel.getDefaultSheet()!;
  final sheet = excel['Activities'];
  final bold = CellStyle(bold: true);
  sheet.appendRow([for (final c in SheetColumn.values) TextCellValue(c.header)]);
  for (var c = 0; c < SheetColumn.values.length; c++) {
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0)).cellStyle = bold;
  }
  CellValue? text(String? s) => s == null || s.trim().isEmpty ? null : TextCellValue(s);
  CellValue? number(double? d) => d == null ? null : DoubleCellValue(d);
  if (withExample) {
    sheet.appendRow([
      for (final c in SheetColumn.values)
        switch (templateExample[c]) {
          null => null,
          // Prices as numbers, as people will type them.
          final v when c == SheetColumn.priceFrom || c == SheetColumn.priceTo => number(double.parse(v)),
          final v => TextCellValue(v),
        },
    ]);
  }
  for (final a in activities) {
    sheet.appendRow([
      TextCellValue(a.name),
      text(a.description),
      text(a.location),
      text(a.placeId),
      number(a.priceMin),
      number(a.priceMax),
      TextCellValue(a.currency),
      text(a.url),
      text(a.personalTypeName),
    ]);
  }
  const widths = [30.0, 40.0, 40.0, 30.0, 11.0, 11.0, 10.0, 36.0, 16.0];
  for (var c = 0; c < widths.length; c++) {
    sheet.setColumnWidth(c, widths[c]);
  }

  final help = excel['How to fill'];
  for (final line in [
    ['Column', 'What to put'],
    ['Name', 'Required. Up to 120 characters.'],
    ['Description', 'Optional.'],
    ['Location', 'Optional. EasyPlan matches it to a Google Maps place when you import.'],
    ['Google place ID', 'Optional. Filled in by EasyPlan exports; keeps the exact place without a search.'],
    ['Price from / Price to', 'Optional numbers, per person (e.g. 10 and 25). "Free" works too.'],
    ['Currency', 'Optional: ${supportedCurrencies.join(', ')}. SGD when empty.'],
    ['Link', 'Optional web address.'],
    ['Label', 'Optional. One of your labels, or a new one (created on import).'],
    if (withExample) ...[
      <String>[],
      [
        'Example row',
        'Row 2 of "Activities" is an example: copy it for your own rows, then change or delete it. '
            'Left exactly as it is, it’s skipped when you import.',
      ],
    ],
  ]) {
    help.appendRow([for (final t in line) TextCellValue(t)]);
  }
  help.setColumnWidth(0, 22);
  help.setColumnWidth(1, 80);

  excel.delete(defaultSheet);
  excel.setDefaultSheet('Activities');
  return excel.encode()!; // encode(), not save(): save() also downloads on the web
}
