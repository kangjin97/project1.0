import 'dart:convert';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:group_planner/data/activity_sheet.dart';
import 'package:group_planner/data/models.dart';

List<int> csv(String text) => utf8.encode(text);

void main() {
  test('a scraped CSV with its own column names and a single Price column', () {
    final sheet = parseActivitySheet(csv('''Title,Address,Price,Website,Category
"Kallang Pickleball, Court 1",Stadium Road Singapore,"\$10-15",kallang.example.com,Pickleball
"He said ""hi""",,free,,
'''), 'courts.csv');
    expect(sheet.error, isNull);
    expect(sheet.rows, hasLength(2));
    final a = sheet.rows[0];
    expect(a.ok, isTrue, reason: a.problems.join());
    expect(a.name, 'Kallang Pickleball, Court 1');
    expect(a.location, 'Stadium Road Singapore');
    expect((a.priceMin, a.priceMax), (10.0, 15.0));
    expect(a.url, 'https://kallang.example.com');
    expect(a.label, 'Pickleball');
    expect(a.line, 2);
    final b = sheet.rows[1];
    expect(b.name, 'He said "hi"');
    expect((b.priceMin, b.priceMax), (0.0, 0.0));
  });

  test('a header like "Court name" is the Name column', () {
    final sheet = parseActivitySheet(csv('Court name,Address\nBishan Hall,Bishan\n'), 'x.csv');
    expect(sheet.error, isNull);
    expect(sheet.rows.single.name, 'Bishan Hall');
    expect(sheet.rows.single.location, 'Bishan');
  });

  test('semicolon CSVs, a BOM and blank rows', () {
    final sheet = parseActivitySheet(csv('﻿Name;Location\r\nDim sum;Jalan Besar\r\n;\r\nKayaking;Pasir Ris\r\n'), 'x.csv');
    expect([for (final r in sheet.rows) r.name], ['Dim sum', 'Kayaking']);
    expect(sheet.rows.last.line, 4);
  });

  test('problems are flagged per row', () {
    final sheet = parseActivitySheet(csv('''Name,Price from,Price to,Currency,Link,Google place ID,Location
,5,,,,,
Too cheap,-3,,,,,
Odd,abc,,,,,
Wrong currency,,,XYZ,,,
Bad link,,,,not a link,,
Place without location,,,,,ChIJabcdefghijk,
Swapped,30,10,usd,,,
'''), 'x.csv');
    Map<String, List<String>> problems = {for (final r in sheet.rows) r.name: r.problems};
    expect(problems[''], ['No name']);
    expect(problems['Too cheap'], ['Price can’t be negative']);
    expect(problems['Odd'], ['Price isn’t a number']);
    expect(problems['Wrong currency']!.single, startsWith('Currency must be one of'));
    expect(problems['Bad link'], ['Link isn’t a web address']);
    expect(problems['Place without location'], ['A Google place ID needs a location']);
    final swapped = sheet.rows.last;
    expect((swapped.ok, swapped.priceMin, swapped.priceMax, swapped.currency), (true, 10.0, 30.0, 'USD'));
  });

  test('whole-file problems', () {
    expect(parseActivitySheet(csv('Title-ish\nx\n'), 'x.csv').error, startsWith('No "Name" column'));
    expect(parseActivitySheet(csv('Name\n'), 'x.csv').error, startsWith('That sheet has no activities'));
    final many = 'Name\n${List.generate(maxImportRows + 1, (i) => 'A$i').join('\n')}\n';
    expect(parseActivitySheet(csv(many), 'x.csv').error, contains('at most $maxImportRows'));
    expect(parseActivitySheet([0, 1, 2, 3], 'x.xlsx').error, startsWith('Couldn’t read that file'));
  });

  test('an EasyPlan export imports back as it was', () {
    final out = activitiesToExcel([
      Activity(
        id: 'a1',
        ownerId: 'u1',
        name: 'Gardens by the Bay',
        description: 'Supertree Grove is free.',
        location: 'Gardens by the Bay, Marina Gardens Drive, Singapore',
        placeId: 'ChIJMxZ-kwQZ2jERdsqftXeWCWI',
        priceMin: 0,
        priceMax: 32,
        currency: 'SGD',
        url: 'https://www.gardensbythebay.com.sg/',
        personalTypeName: 'Outdoors',
        createdAt: DateTime.utc(2026, 10, 1),
        updatedAt: DateTime.utc(2026, 10, 1),
      ),
      Activity(id: 'a2', ownerId: 'u1', name: 'Just a name', createdAt: DateTime.utc(2026), updatedAt: DateTime.utc(2026)),
    ]);
    final sheet = parseActivitySheet(out, 'EasyPlan activities.xlsx');
    expect(sheet.error, isNull);
    final a = sheet.rows.first;
    expect(a.ok, isTrue, reason: a.problems.join());
    expect([a.name, a.description, a.location, a.placeId, a.currency, a.url, a.label], [
      'Gardens by the Bay',
      'Supertree Grove is free.',
      'Gardens by the Bay, Marina Gardens Drive, Singapore',
      'ChIJMxZ-kwQZ2jERdsqftXeWCWI',
      'SGD',
      'https://www.gardensbythebay.com.sg/',
      'Outdoors',
    ]);
    expect((a.priceMin, a.priceMax), (0.0, 32.0));
    expect(sheet.rows.last.name, 'Just a name');
    expect(sheet.rows.last.ok, isTrue);
  });

  test('the template has an example row, which an import skips until it is changed', () {
    final template = activitiesToExcel(const [], withExample: true);
    // Untouched: nothing to import.
    expect(parseActivitySheet(template, 'template.xlsx').error, startsWith('That sheet only has the template’s example row'));
    final rows = Excel.decodeBytes(template).tables['Activities']!.rows;
    expect(rows, hasLength(2));
    final example = rows[1];
    expect(example[SheetColumn.name.index]?.value, TextCellValue(templateExample[SheetColumn.name]!));
    expect(example[SheetColumn.priceFrom.index]?.value, anyOf(isA<IntCellValue>(), isA<DoubleCellValue>()), reason: 'prices are numbers');
    expect(example[SheetColumn.placeId.index]?.value, isNull);
    expect(Excel.decodeBytes(activitiesToExcel(const [])).tables['Activities']!.rows, hasLength(1));

    // The example is really there, prices as numbers, and reads back as a good row once edited.
    final edited = csv(
      'Name,Description,Location,Google place ID,Price from,Price to,Currency,Link,Label\n'
      '"${templateExample[SheetColumn.name]}","${templateExample[SheetColumn.description]}",'
      '${templateExample[SheetColumn.location]},,10,15,SGD,${templateExample[SheetColumn.link]},Pickleball\n'
      'My court,,Toa Payoh,,10,15,SGD,,Pickleball\n',
    );
    final sheet = parseActivitySheet(edited, 'x.csv');
    expect([for (final r in sheet.rows) r.name], ['My court'], reason: 'an unchanged example row is skipped anywhere');

    final changed = parseActivitySheet(
      csv('Name,Location,Price from,Price to,Currency,Link,Label,Description\n'
          '"${templateExample[SheetColumn.name]}",${templateExample[SheetColumn.location]},10,20,SGD,'
          '${templateExample[SheetColumn.link]},Pickleball,"${templateExample[SheetColumn.description]}"\n'),
      'x.csv',
    );
    expect(changed.rows.single.ok, isTrue, reason: 'one changed cell (price to 20) makes it a real row');
    expect(changed.rows.single.priceMax, 20.0);
  });

  test('exports never include the example row', () {
    final out = activitiesToExcel([
      Activity(id: 'a', ownerId: 'u', name: 'Only me', createdAt: DateTime.utc(2026), updatedAt: DateTime.utc(2026)),
    ]);
    expect([for (final r in parseActivitySheet(out, 'x.xlsx').rows) r.name], ['Only me']);
  });

  group('duplicates', () {
    Activity have(String name, {String? location, String? placeId}) => Activity(
      id: name,
      ownerId: 'u1',
      name: name,
      location: location,
      placeId: placeId,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );

    test('same name and location text, ignoring case and spaces', () {
      final check = DuplicateCheck([have('Dim Sum', location: 'Jalan Besar')]);
      expect(check.contains(' dim sum ', location: 'JALAN BESAR'), isTrue);
      expect(check.contains('Dim sum', location: 'Chinatown'), isFalse);
      expect(check.contains('Other', location: 'Jalan Besar'), isFalse);
    });

    test('no location matches no location only', () {
      final check = DuplicateCheck([have('Picnic')]);
      expect(check.contains('Picnic'), isTrue);
      expect(check.contains('Picnic', location: 'Botanic Gardens'), isFalse);
    });

    test('a re-imported sheet matches on the Google place, whose text differs from the sheet', () {
      // What the first import saved: Google's text and place.
      final check = DuplicateCheck([
        have('Bishan Pickleball', location: 'Bishan Sports Hall, Bishan Street 14, Singapore', placeId: 'ChIJbishan0001'),
      ]);
      // The same sheet row again: its text doesn't match ...
      expect(check.contains('Bishan Pickleball', location: 'Bishan Sports Hall'), isFalse);
      // ... but the place it's matched to does.
      expect(check.hasPlace('Bishan Pickleball', 'ChIJbishan0001'), isTrue);
      expect(check.hasPlace('Another court', 'ChIJbishan0001'), isFalse);
      expect(check.contains('bishan pickleball', location: 'Bishan', placeId: 'ChIJbishan0001'), isTrue);
    });

    test('rows added while reading a sheet count for later rows', () {
      final check = DuplicateCheck(const []);
      expect(check.contains('Kayaking', location: 'Pasir Ris'), isFalse);
      check.add('Kayaking', location: 'Pasir Ris');
      expect(check.contains('kayaking', location: 'pasir ris'), isTrue);
      check.add('Kayaking', location: 'Pasir Ris Park, Singapore', placeId: 'ChIJpasirris01');
      expect(check.hasPlace('Kayaking', 'ChIJpasirris01'), isTrue);
    });
  });

  test('the preview words prices like the activity list', () {
    final sheet = parseActivitySheet(csv('Name,Price\nA,free\nB,\$10-15\nC,12\nD,\n'), 'x.csv');
    expect([for (final r in sheet.rows) r.priceLabel], ['Free', 'SGD 10–15', 'SGD 12', null]);
  });

  test('prices', () {
    expect(parsePrice(r'$1,200.50'), 1200.5);
    expect(parsePrice('SGD 15'), 15);
    expect(parsePrice('Free'), 0);
    expect(parsePrice(''), isNull);
    expect(parsePriceRange('10 – 20'), (10.0, 20.0));
    expect(parsePriceRange('10 to 20'), (10.0, 20.0));
    expect(parsePriceRange(r'$15'), (15.0, 15.0));
  });
}
