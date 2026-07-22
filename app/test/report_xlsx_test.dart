// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: LicenseRef-Proprietary
// Smoke tests for the shareable report writer: it produces a valid workbook
// with the title, owner line, summary, per-account groups, and a grand total.

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart' show ColorScheme, Colors;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ihaveannuities/core/models.dart';
import 'package:ihaveannuities/core/payoff.dart';
import 'package:ihaveannuities/data/market.dart';
import 'package:ihaveannuities/data/portfolio_store.dart';
import 'package:ihaveannuities/data/report_xlsx.dart';
import 'package:ihaveannuities/data/tracker_xlsx.dart';
import 'package:ihaveannuities/ui/portfolio_table.dart';

Holding _h(String issuer, AccountType account,
        {String index = '^GSPC', double initial = 100}) =>
    Holding(
      issuer: issuer,
      index: index,
      account: account,
      cap: 0.12,
      participation: 1.0,
      floor: -0.10,
      floorType: FloorType.hard,
      strike: 100,
      currentLevel: 112,
      openDate: DateTime(2024, 1, 2),
      lastReset: DateTime(2026, 1, 2),
      maturity: DateTime(2030, 1, 2),
      nextReset: DateTime(2027, 1, 2),
      resetFreq: ResetFreq.annual,
      initial: initial,
    );

/// All cell text across the report sheet, concatenated (TextCellValue embeds
/// its text in toString()).
String _allText(List<int> bytes) {
  final ex = Excel.decodeBytes(bytes);
  final sheet = ex['Portfolio Report'];
  final b = StringBuffer();
  for (final row in sheet.rows) {
    for (final cell in row) {
      if (cell?.value != null) b.write('${cell!.value} | ');
    }
  }
  return b.toString();
}

/// The worksheet XML inside the .xlsx zip (where the outline/freeze live).
String _worksheetXml(List<int> bytes) {
  final ws = ZipDecoder().decodeBytes(bytes).files.firstWhere(
      (f) => f.name.contains('worksheets/') && f.name.endsWith('.xml'));
  return utf8.decode(ws.content as List<int>);
}

String _acct(Holding h) => h.account.label; // group-by-Type value extractor

/// Numeric value out of a decoded cell (report money cells are Doubles *1000).
double? _numeric(CellValue? v) {
  if (v is DoubleCellValue) return v.value;
  if (v is IntCellValue) return v.value.toDouble();
  return null;
}

/// col0 text of a decoded row ('' when empty) — used to classify band rows.
String _col0(List<Data?> row) =>
    (row.isNotEmpty ? row[0]?.value : null)?.toString() ?? '';

/// A minimal Holding builder that lets a test vary cap/index/floor.
Holding _mk(
  String issuer, {
  String index = '^GSPC',
  double? cap = 0.12,
  double floor = -0.10,
  FloorType floorType = FloorType.hard,
  AccountType account = AccountType.ira,
  double initial = 100,
}) =>
    Holding(
      issuer: issuer,
      index: index,
      account: account,
      cap: cap,
      participation: 1.0,
      floor: floor,
      floorType: floorType,
      strike: 100,
      currentLevel: 112,
      openDate: DateTime(2024, 1, 2),
      lastReset: DateTime(2026, 1, 2),
      maturity: DateTime(2030, 1, 2),
      nextReset: DateTime(2027, 1, 2),
      resetFreq: ResetFreq.annual,
      initial: initial,
    );

void main() {
  final asOf = DateTime(2026, 6, 12);
  final gen = DateTime(2026, 7, 17);

  test('grouped report: title, owner, summary, group bands, and total', () {
    final holdings = [
      _h('HSBC', AccountType.ira, index: '^NDX'),
      _h('CITI', AccountType.ira),
      _h('BNP', AccountType.roth),
    ];
    final bytes = writeReport(holdings,
        asOf: asOf,
        generatedOn: gen,
        preparedFor: 'Jane Doe',
        groupBy: 'Type',
        groupValueOf: _acct);
    expect(bytes, isNotEmpty);

    final text = _allText(bytes);
    expect(text, contains('Portfolio Report'));
    expect(text, contains('Prepared for Jane Doe'));
    expect(text, contains('SUMMARY'));
    expect(text, contains('IRA')); // group band label "IRA  (2)"
    expect(text, contains('ROTH'));
    expect(text, contains('TOTAL'));
    expect(text, contains('HSBC'));
    // Friendly index name, not the raw symbol.
    expect(text, contains('Nasdaq-100'));
    expect(text, isNot(contains('^NDX')));
    // Disclaimer present.
    expect(text, contains('not investment advice'));
  });

  test('grouped report has a collapsible outline (starts expanded) + freeze', () {
    final holdings = [
      _h('HSBC', AccountType.ira),
      _h('CITI', AccountType.ira),
      _h('BNP', AccountType.roth),
    ];
    final bytes = writeReport(holdings,
        asOf: asOf,
        generatedOn: gen,
        preparedFor: 'Jane', // owner line → header at row 12 → freeze G13
        groupBy: 'Type',
        groupValueOf: _acct);

    final archive = ZipDecoder().decodeBytes(bytes);
    final ws = archive.files.firstWhere(
        (f) => f.name.contains('worksheets/') && f.name.endsWith('.xml'));
    final xml = utf8.decode(ws.content as List<int>);

    expect(xml, contains('summaryBelow="0"'));
    expect(xml, contains('outlineLevel="1"'));
    expect(xml, isNot(contains('hidden="1"'))); // starts expanded
    expect(xml, contains('state="frozen"'));
    expect(xml, contains('topLeftCell="G13"'));
    expect(() => Excel.decodeBytes(bytes), returnsNormally);
  });

  test('ungrouped report is a flat list: no group outline', () {
    final holdings = [_h('CITI', AccountType.ira), _h('BNP', AccountType.roth)];
    final bytes = writeReport(holdings, asOf: asOf, generatedOn: gen); // no groupBy

    final text = _allText(bytes);
    expect(text, contains('Portfolio Report'));
    expect(text, contains('TOTAL'));
    expect(text, contains('CITI'));

    final archive = ZipDecoder().decodeBytes(bytes);
    final ws = archive.files.firstWhere(
        (f) => f.name.contains('worksheets/') && f.name.endsWith('.xml'));
    final xml = utf8.decode(ws.content as List<int>);
    expect(xml, isNot(contains('outlineLevel="1"'))); // nothing grouped
    // No owner line → header one row higher → freeze at G12.
    expect(xml, contains('topLeftCell="G12"'));
  });

  test('no owner line when preparedFor is omitted or blank', () {
    final text = _allText(writeReport([_h('X', AccountType.nonQual)],
        asOf: asOf, generatedOn: gen));
    expect(text, isNot(contains('Prepared for')));
  });

  // End-to-end: the report mirrors the browser's grouping for EVERY dimension
  // (the "grouping by Protection didn't group" regression). Drives the real app
  // path — setGroupBy + setSort, orderedHoldings, then exportReportXlsx.
  group('report export mirrors browser grouping (all dimensions)', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    final cs = ColorScheme.fromSeed(seedColor: Colors.blue);
    final market = Market(
        asOf: DateTime(2026, 6, 14),
        spx: 7431, ndx: 29635, rut: 2943, dow: 44012, comp: 23501);

    PortfolioStore seeded() {
      final holdings = parseTracker(
          File('../data/example-portfolio.xlsx').readAsBytesSync());
      return PortfolioStore(client: MockClient((_) async => http.Response('x', 500)))
        ..debugSeed(holdings, market);
    }

    for (final dim in PortfolioStore.groupDimensions) {
      test('grouped by $dim → bands for every distinct value + outline', () async {
        final store = seeded();
        await store.setGroupBy(dim);
        await store.setSort(
            PortfolioTable.columnIndexForDimension(dim, cs), true);
        final ordered = PortfolioTable.orderedHoldings(store, market.asOf, cs);
        final bytes = store.exportReportXlsx(
            ordered: ordered,
            groupBy: store.groupBy,
            groupValueOf: (h) => PortfolioTable.groupValueOf(h, store.groupBy));

        // Every distinct group value appears as a band label ("value  (n)").
        final values = {
          for (final h in store.holdings)
            PortfolioTable.groupValueOf(h, dim)
        };
        final text = _allText(bytes);
        for (final v in values) {
          expect(text, contains('$v  ('),
              reason: '$dim: missing band for "$v"');
        }
        // Grouped → the collapsible outline is present.
        expect(_worksheetXml(bytes), contains('outlineLevel="1"'),
            reason: '$dim: no outline');
      });
    }

    test('ungrouped → flat list, no outline', () async {
      final store = seeded();
      final ordered = PortfolioTable.orderedHoldings(store, market.asOf, cs);
      final bytes = store.exportReportXlsx(ordered: ordered); // groupBy=''
      expect(_allText(bytes), contains('TOTAL'));
      expect(_worksheetXml(bytes), isNot(contains('outlineLevel="1"')));
    });

    // Regression: grouped + sorted by a money column must order the GROUPS by
    // their subtotal (not by whichever single holding ranks highest). Group by
    // Issuer, sort by Unrealized $ desc → issuer bands descend by their
    // Unrealized $ subtotal.
    test('groups order by their subtotal, not their top holding', () async {
      final store = seeded();
      await store.setGroupBy('Issuer');
      final unrealCol = PortfolioTable.columnLabels(cs).indexOf('Unrealized \$');
      await store.setSort(unrealCol, false); // descending
      final ordered = PortfolioTable.orderedHoldings(store, market.asOf, cs);

      // Group appearance order in the ordered list = the band order.
      final bandOrder = <String>[];
      final subtotal = <String, double>{};
      for (final h in ordered) {
        final v = PortfolioTable.groupValueOf(h, 'Issuer');
        if (!subtotal.containsKey(v)) bandOrder.add(v);
        subtotal[v] = (subtotal[v] ?? 0) + h.projGainDollarsK;
      }

      // Bands are in non-increasing subtotal order.
      for (var i = 1; i < bandOrder.length; i++) {
        expect(subtotal[bandOrder[i - 1]]! >= subtotal[bandOrder[i]]! - 1e-9, isTrue,
            reason: 'band "${bandOrder[i - 1]}" (${subtotal[bandOrder[i - 1]]}) '
                'should not sit above "${bandOrder[i]}" (${subtotal[bandOrder[i]]})');
      }
    });
  });

  // Reconciliation: every group subtotal band must sum back to the grand TOTAL
  // for each money column. This is the same failure class as the group-order
  // bug (mis-bucketing / double-counting a holding into the wrong band).
  test('report group subtotals reconcile to the grand TOTAL', () {
    final holdings =
        parseTracker(File('../data/example-portfolio.xlsx').readAsBytesSync());
    final bytes = writeReport(holdings,
        asOf: asOf,
        generatedOn: gen,
        groupBy: 'Issuer',
        groupValueOf: (h) => h.issuer);

    final sheet = Excel.decodeBytes(bytes)['Portfolio Report'];

    // Sum a column across all GROUP bands (col0 contains '('); read the same
    // column from the grand TOTAL band (col0 == 'TOTAL').
    double groupSum(int col) {
      var s = 0.0;
      var bands = 0;
      for (final row in sheet.rows) {
        final t = _col0(row);
        if (t != 'TOTAL' && t.contains('(')) {
          bands++;
          s += _numeric(col < row.length ? row[col]?.value : null) ?? 0;
        }
      }
      expect(bands, greaterThan(1), reason: 'expected multiple issuer bands');
      return s;
    }

    double totalOf(int col) {
      for (final row in sheet.rows) {
        if (_col0(row) == 'TOTAL') {
          return _numeric(col < row.length ? row[col]?.value : null) ?? 0;
        }
      }
      fail('no TOTAL band found');
    }

    // col 5 = Principal, col 7 = Unrealized $, col 8 = Projected Value.
    for (final col in const [5, 7, 8]) {
      expect(groupSum(col), closeTo(totalOf(col), 1e-6),
          reason: 'column $col: group subtotals do not reconcile to TOTAL');
    }
  });

  test('report renders edge cell semantics', () {
    // A grouped report with an uncapped holding and a worst-of income note.
    final holdings = [
      _mk('ACME', cap: null), // Uncapped
      _mk('BETA', index: 'SPX/NDX'), // Worst-of friendly index
      _mk('GAMMA', floor: 0, floorType: FloorType.none), // protection == None
    ];
    final text = _allText(writeReport(holdings,
        asOf: asOf,
        generatedOn: gen,
        groupBy: 'Issuer',
        groupValueOf: (h) => h.issuer));

    expect(text, contains('Uncapped'));
    expect(text, contains('Worst-of'));
    expect(text, contains('None')); // FloorType.none → protection value "None"
  });

  test('empty portfolio exports a valid workbook', () {
    final bytes = writeReport(const <Holding>[], asOf: asOf, generatedOn: gen);
    expect(() => Excel.decodeBytes(bytes), returnsNormally);

    final sheet = Excel.decodeBytes(bytes)['Portfolio Report'];
    var foundTotal = false;
    for (final row in sheet.rows) {
      if (_col0(row) == 'TOTAL') {
        foundTotal = true;
        final principal = _numeric(row.length > 5 ? row[5]?.value : null) ?? 0;
        expect(principal, closeTo(0, 1e-6)); // no holdings → zero principal
      }
    }
    expect(foundTotal, isTrue);

    // The store export path also decodes normally for an empty portfolio.
    SharedPreferences.setMockInitialValues({});
    final store =
        PortfolioStore(client: MockClient((_) async => http.Response('x', 500)));
    expect(() => Excel.decodeBytes(store.exportReportXlsx(ordered: const [])),
        returnsNormally);
  });
}
