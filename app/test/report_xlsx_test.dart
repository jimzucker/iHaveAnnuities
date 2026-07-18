// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: LicenseRef-Proprietary
// Smoke tests for the shareable report writer: it produces a valid workbook
// with the title, owner line, summary, per-account groups, and a grand total.

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ihaveannuities/core/models.dart';
import 'package:ihaveannuities/core/payoff.dart';
import 'package:ihaveannuities/data/report_xlsx.dart';

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

void main() {
  final asOf = DateTime(2026, 6, 12);
  final gen = DateTime(2026, 7, 17);

  test('report contains title, owner, summary, account groups, and total', () {
    final holdings = [
      _h('HSBC', AccountType.ira, index: '^NDX'),
      _h('CITI', AccountType.ira),
      _h('BNP', AccountType.roth),
    ];
    final bytes =
        writeReport(holdings, asOf: asOf, generatedOn: gen, preparedFor: 'Jane Doe');
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

  test('account groups get a collapsible outline (starts expanded)', () {
    final holdings = [
      _h('HSBC', AccountType.ira),
      _h('CITI', AccountType.ira),
      _h('BNP', AccountType.roth),
    ];
    final bytes = writeReport(holdings, asOf: asOf, generatedOn: gen);

    // Crack the .xlsx (a zip) and read the worksheet XML.
    final archive = ZipDecoder().decodeBytes(bytes);
    final ws = archive.files.firstWhere(
        (f) => f.name.contains('worksheets/') && f.name.endsWith('.xml'));
    final xml = utf8.decode(ws.content as List<int>);

    // Summary sits above the detail; member rows are grouped (outline level 1)
    // but NOT hidden — the groups open expanded, collapsible via the ± controls.
    expect(xml, contains('summaryBelow="0"'));
    expect(xml, contains('outlineLevel="1"'));
    expect(xml, isNot(contains('hidden="1"')));
    // Freeze at G13 (columns A–F, rows 1–12).
    expect(xml, contains('state="frozen"'));
    expect(xml, contains('topLeftCell="G13"'));
    // Still a valid workbook the excel reader can parse.
    expect(() => Excel.decodeBytes(bytes), returnsNormally);
  });

  test('no owner line when preparedFor is omitted or blank', () {
    final text = _allText(writeReport([_h('X', AccountType.nonQual)],
        asOf: asOf, generatedOn: gen));
    expect(text, isNot(contains('Prepared for')));
  });
}
