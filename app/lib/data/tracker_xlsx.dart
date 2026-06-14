//
//  tracker_xlsx.dart
//  iHaveAnnuities
//
//  Copyright 2026 Jim Zucker
//  SPDX-License-Identifier: Apache-2.0
//
// Read/write the Zucker Annuity Tracker .xlsx schema. The same format is used
// for import, the shipped example/template, and what the app exports — so the
// user's real spreadsheet round-trips.

import 'package:excel/excel.dart';

import '../core/models.dart';
import '../core/payoff.dart';
import 'xlsx_reader.dart';

const _sheetName = 'Annuity Tracker';

const headers = <String>[
  'Issuer', 'Index Gain %', 'Proj Gain @ Reset', 'Index', 'CAP', 'Part.',
  'Floor', 'Floor Type', 'Strike', 'Open', 'Last Reset', 'Maturity',
  'Days to Maturity', 'Reset Freq', 'Next Reset', 'Days to Reset',
  'Initial (\$000)', 'Realized (\$000)', 'Proj Value @ Reset (\$000)',
  'Proj \$ Gain @ Reset (\$000)', 'Type',
];

String? _str(List<dynamic> row, Map<String, int> h, String key) {
  final i = h[key];
  if (i == null || i >= row.length) return null;
  return row[i]?.toString().trim();
}

double? _num(List<dynamic> row, Map<String, int> h, String key) {
  final i = h[key];
  if (i == null || i >= row.length) return null;
  final v = row[i];
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.replaceAll(RegExp(r'[\$,%\s]'), ''));
  return null;
}

DateTime? _date(List<dynamic> row, Map<String, int> h, String key) {
  final i = h[key];
  if (i == null || i >= row.length) return null;
  final v = row[i];
  if (v is DateTime) return v;
  if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
  return null;
}

ResetFreq _resetFreq(String? s) => switch ((s ?? '').toLowerCase()) {
      'monthly' => ResetFreq.monthly,
      '4-year' => ResetFreq.y4,
      '5-year' => ResetFreq.y5,
      '6-year' => ResetFreq.y6,
      _ => ResetFreq.annual,
    };

AccountType _account(String? s) => switch ((s ?? '').toLowerCase()) {
      'ira' => AccountType.ira,
      'roth' => AccountType.roth,
      _ => AccountType.nonQual,
    };

/// Parse holdings from tracker `.xlsx` [bytes]. Skips the title/legend rows,
/// maps columns by header name, and stops at the first `TOTAL` row.
List<Holding> parseTracker(List<int> bytes) {
  final tables = XlsxReader.decode(bytes);
  if (tables.isEmpty) throw const FormatException('Workbook has no sheets');
  final rows =
      tables.containsKey(_sheetName) ? tables[_sheetName]! : tables.values.first;

  final headerIdx = rows.indexWhere((r) => r.any((c) {
        final v = c?.toString().trim();
        return v == 'Issuer' || v == 'Position';
      }));
  if (headerIdx < 0) {
    throw const FormatException('No "Issuer"/"Position" header row found');
  }
  final h = <String, int>{};
  final hrow = rows[headerIdx];
  for (var i = 0; i < hrow.length; i++) {
    final name = hrow[i]?.toString().trim();
    if (name != null && name.isNotEmpty) h[name] = i;
  }

  final out = <Holding>[];
  for (var ri = headerIdx + 1; ri < rows.length; ri++) {
    final r = rows[ri];
    // Row control: stop at a TOTAL row; skip blanks. Position (if present) is
    // ignored as data — it is recomputed from issuer/floor/maturity.
    final label =
        _str(r, h, 'Position') ?? (r.isNotEmpty ? r.first?.toString().trim() : null);
    if (label != null && label.toUpperCase().startsWith('TOTAL')) break;
    final issuer = _str(r, h, 'Issuer');
    if (issuer == null || issuer.isEmpty) continue;

    final capStr = _str(r, h, 'CAP');
    final double? cap = (capStr != null && capStr.toLowerCase().contains('uncap'))
        ? null
        : _num(r, h, 'CAP');
    final floorType = (_str(r, h, 'Floor Type') ?? 'Hard').toLowerCase() == 'soft'
        ? FloorType.soft
        : FloorType.hard;
    final strike = _num(r, h, 'Strike') ?? 0;
    final indexGain = _num(r, h, 'Index Gain %') ?? 0;
    final freq = _resetFreq(_str(r, h, 'Reset Freq'));
    final isNote = freq == ResetFreq.monthly;
    final open = _date(r, h, 'Open') ?? DateTime(2026);

    out.add(Holding(
      issuer: issuer,
      index: _str(r, h, 'Index') ?? 'SPX',
      account: _account(_str(r, h, 'Type')),
      cap: cap,
      participation: _num(r, h, 'Part.') ?? 1.0,
      floor: _num(r, h, 'Floor') ?? 0.0,
      floorType: floorType,
      strike: strike,
      currentLevel: strike * (1 + indexGain),
      openDate: open,
      lastReset: _date(r, h, 'Last Reset') ?? open,
      maturity: _date(r, h, 'Maturity') ?? open,
      nextReset: _date(r, h, 'Next Reset') ?? open,
      resetFreq: freq,
      initial: _num(r, h, 'Initial (\$000)') ?? 100.0,
      realized: _num(r, h, 'Realized (\$000)') ?? 0.0,
      isIncomeNote: isNote,
      couponProj: isNote ? (_num(r, h, 'Proj Gain @ Reset') ?? 0.0) : 0.0,
    ));
  }
  return out;
}

CellValue? _dateCell(DateTime d) => DateCellValue(year: d.year, month: d.month, day: d.day);

/// Serialize [holdings] to tracker `.xlsx` bytes, [asOf] / [prices] in the title.
List<int> writeTracker(
  List<Holding> holdings, {
  required DateTime asOf,
  required Map<String, double> prices,
}) {
  final excel = Excel.createExcel();
  final def = excel.getDefaultSheet();
  if (def != null && def != _sheetName) excel.rename(def, _sheetName);
  final s = excel[_sheetName];

  s.appendRow([
    TextCellValue('ZUCKER ANNUITY TRACKER — Updated '
        '${asOf.month}/${asOf.day}/${asOf.year} '
        '(prices: SPX ${prices['SPX']}  NDX ${prices['NDX']}  RUT ${prices['RUT']})'),
  ]);
  s.appendRow([
    TextCellValue('Floor 0% = floor; negative Hard = buffer; negative Soft = '
        'barrier | \$ columns in \$000s'),
  ]);
  s.appendRow([for (final hd in headers) TextCellValue(hd)]);

  for (final x in holdings) {
    s.appendRow(<CellValue?>[
      TextCellValue(x.issuer),
      DoubleCellValue(x.indexGain),
      DoubleCellValue(x.projGain),
      TextCellValue(x.index),
      x.cap == null ? TextCellValue('Uncapped') : DoubleCellValue(x.cap!),
      DoubleCellValue(x.participation),
      DoubleCellValue(x.floor),
      TextCellValue(x.protectionType),
      DoubleCellValue(x.strike),
      _dateCell(x.openDate),
      _dateCell(x.lastReset),
      _dateCell(x.maturity),
      IntCellValue(x.daysToMaturity(asOf)),
      TextCellValue(x.resetFreq.label),
      _dateCell(x.nextReset),
      IntCellValue(x.daysToReset(asOf)),
      DoubleCellValue(x.initial),
      DoubleCellValue(x.realized),
      DoubleCellValue(x.projValueK),
      DoubleCellValue(x.projGainDollarsK),
      TextCellValue(x.account.label),
    ]);
  }
  return excel.encode()!;
}
