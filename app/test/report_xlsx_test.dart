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
  });
}
