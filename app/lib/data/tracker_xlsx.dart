// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: Apache-2.0
// Read/write the Zucker Annuity Tracker .xlsx schema v1.2. The same format is
// used for import, the shipped example/template, and what the app exports — so
// the user's real spreadsheet round-trips.
//
// v1.2 orders columns "Identity → Inputs → Outcome → Timing → Terms" (matches
// the on-screen table): Initial sits next to Proj Value, and the monitored
// reset/maturity dates come before the static contract terms. The reader maps
// columns BY HEADER NAME, so v1.0/v1.1 files (and the user's real tracker) still
// import — and re-exporting converts them to v1.2 order. The reader also keeps a
// one-cycle compatibility layer for the legacy vocabulary (`Absolute`/`Hard`/
// `Soft` floor type with title-case-or-not; `4-Year`/`5-Year`/`6-Year` reset
// freq → `Inception`; text `Uncapped` CAP → uncapped). `Position` (derived)
// stays in column A and `NDX_Strike`/`RUT_Strike` for worst-of stay in W/X.

import 'package:excel/excel.dart';

import '../core/models.dart';
import '../core/payoff.dart';
import 'xlsx_reader.dart';

const _sheetName = 'Annuity Tracker';

/// v1.2 column order (A → X): Identity → Inputs → Outcome → Timing → Terms.
const headers = <String>[
  'Position', // A — derived, output-only
  'Issuer', // B — identity
  'Type',
  'Index',
  'Floor Type',
  'Initial (\$000)', // F — inputs
  'Realized (\$000)',
  'Proj Value @ Reset (\$000)', // H — outcome
  'Proj \$ Gain @ Reset (\$000)',
  'Proj Gain @ Reset',
  'Index Gain %',
  'Next Reset', // L — timing (monitor)
  'Days to Reset',
  'Maturity',
  'Days to Maturity',
  'CAP', // P — terms (static)
  'Part.',
  'Floor',
  'Strike',
  'Reset Freq',
  'Open',
  'Last Reset',
  'NDX_Strike', // W — populated only for worst-of
  'RUT_Strike', // X — populated only for worst-of
];

/// Numeric sentinel for an uncapped CAP column (= 999%).
const double kUncappedSentinel = 9.99;

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

/// v1.0 + legacy: `Inception` / `Annual` / `Monthly` plus legacy `4-Year` /
/// `5-Year` / `6-Year` / `N-Year` → `Inception`. Case-insensitive. Default
/// `Annual`.
ResetFreq _resetFreq(String? s) {
  final v = (s ?? '').toLowerCase().trim();
  if (v == 'monthly') return ResetFreq.monthly;
  if (v == 'inception') return ResetFreq.inception;
  if (RegExp(r'^\d+-year$').hasMatch(v)) return ResetFreq.inception;
  return ResetFreq.annual;
}

AccountType _account(String? s) => switch ((s ?? '').toLowerCase()) {
      'ira' => AccountType.ira,
      'roth' => AccountType.roth,
      _ => AccountType.nonQual,
    };

/// v1.0 + legacy: `Soft` → soft (barrier); anything else → hard. The
/// `Protected` value is derived in the model when `floor == 0`, so it never
/// needs its own FloorType enum value.
FloorType _floorType(String? s) =>
    (s ?? 'Hard').toLowerCase() == 'soft' ? FloorType.soft : FloorType.hard;

/// CAP read: numeric `9.99` (v1.0 sentinel) OR string containing `uncap`
/// (legacy text) both mean uncapped → null. Otherwise parse as fraction.
double? _readCap(List<dynamic> r, Map<String, int> h) {
  final raw = _str(r, h, 'CAP');
  if (raw != null && raw.toLowerCase().contains('uncap')) return null;
  final n = _num(r, h, 'CAP');
  if (n == null) return null;
  if ((n - kUncappedSentinel).abs() < 1e-9) return null;
  return n;
}

/// Parse holdings from tracker `.xlsx` [bytes]. Skips the title/legend rows,
/// maps columns by header name, and stops at the first `TOTAL` row. The
/// `Position` column (if present) is ignored — it is regenerated on write.
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
    // ignored as data — it is regenerated from issuer/floor/maturity.
    final label =
        _str(r, h, 'Position') ?? (r.isNotEmpty ? r.first?.toString().trim() : null);
    if (label != null && label.toUpperCase().startsWith('TOTAL')) break;
    final issuer = _str(r, h, 'Issuer');
    if (issuer == null || issuer.isEmpty) continue;

    final cap = _readCap(r, h);
    final floorType = _floorType(_str(r, h, 'Floor Type'));
    final strike = _num(r, h, 'Strike') ?? 0;
    final indexGain = _num(r, h, 'Index Gain %') ?? 0;
    final freq = _resetFreq(_str(r, h, 'Reset Freq'));
    final isNote = freq == ResetFreq.monthly;
    final open = _date(r, h, 'Open') ?? DateTime(2026);

    out.add(Holding(
      issuer: issuer,
      index: _str(r, h, 'Index') ?? '^GSPC',
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
      ndxStrike: _num(r, h, 'NDX_Strike'),
      rutStrike: _num(r, h, 'RUT_Strike'),
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
    TextCellValue('Floor Type: Protected (0% floor), Hard (buffer — '
        'absorbs first |floor|), Soft (barrier — full loss if breached) | '
        'CAP 9.99 = uncapped | \$ columns in \$000s'),
  ]);
  s.appendRow([for (final hd in headers) TextCellValue(hd)]);

  for (final x in holdings) {
    final isWorstOf = x.index.contains('/');
    s.appendRow(<CellValue?>[
      TextCellValue(dedupedPosition(x, holdings)), // A Position
      TextCellValue(x.issuer), // B Issuer
      TextCellValue(x.account.label), // C Type
      TextCellValue(x.index), // D Index
      TextCellValue(x.protectionType), // E Floor Type
      DoubleCellValue(x.initial), // F Initial
      DoubleCellValue(x.realized), // G Realized
      DoubleCellValue(x.projValueK), // H Proj Value
      DoubleCellValue(x.projGainDollarsK), // I Proj $ Gain
      DoubleCellValue(x.projGain), // J Proj Gain @ Reset
      DoubleCellValue(x.indexGain), // K Index Gain %
      _dateCell(x.nextReset), // L Next Reset
      IntCellValue(x.daysToReset(asOf)), // M Days to Reset
      _dateCell(x.maturity), // N Maturity
      IntCellValue(x.daysToMaturity(asOf)), // O Days to Maturity
      DoubleCellValue(x.cap ?? kUncappedSentinel), // P CAP
      DoubleCellValue(x.participation), // Q Part.
      DoubleCellValue(x.floor), // R Floor
      DoubleCellValue(x.strike), // S Strike
      TextCellValue(x.resetFreq.label), // T Reset Freq
      _dateCell(x.openDate), // U Open
      _dateCell(x.lastReset), // V Last Reset
      isWorstOf && x.ndxStrike != null ? DoubleCellValue(x.ndxStrike!) : null, // W
      isWorstOf && x.rutStrike != null ? DoubleCellValue(x.rutStrike!) : null, // X
    ]);
  }

  // ---- TOTAL row (mirrors the on-screen totals) ----
  final totInitial = holdings.fold(0.0, (a, h) => a + h.initial);
  final totRealized = holdings.fold(0.0, (a, h) => a + h.realized);
  final totProjValue = holdings.fold(0.0, (a, h) => a + h.projValueK);
  final total = List<CellValue?>.filled(headers.length, null);
  total[0] = TextCellValue('TOTAL');
  total[5] = DoubleCellValue(totInitial); // F Initial
  total[6] = DoubleCellValue(totRealized); // G Realized
  total[7] = DoubleCellValue(totProjValue); // H Proj Value
  total[8] = DoubleCellValue(totProjValue - totInitial - totRealized); // I Proj $ Gain (unrealized)
  s.appendRow(total);

  _styleTracker(s, holdings.length);
  return excel.encode()!;
}

/// Apply header styling, per-column number formats, a bold total row, and
/// column widths so the exported file reads like the on-screen table.
void _styleTracker(Sheet s, int nRows) {
  const headerRowIdx = 2; // title(0), legend(1), header(2)
  final totalRowIdx = headerRowIdx + nRows + 1;

  final pctF = NumFormat.standard_10; // 0.00%
  final curF = CustomNumericNumFormat(formatCode: '\$#,##0.00');
  final numF = NumFormat.standard_4; // #,##0.00
  final dateF = NumFormat.standard_15; // d-mmm-yy
  final byHeader = <String, NumFormat>{
    'Initial (\$000)': curF, 'Realized (\$000)': curF,
    'Proj Value @ Reset (\$000)': curF, 'Proj \$ Gain @ Reset (\$000)': curF,
    'Proj Gain @ Reset': pctF, 'Index Gain %': pctF,
    'CAP': pctF, 'Part.': pctF, 'Floor': pctF,
    'Next Reset': dateF, 'Maturity': dateF, 'Open': dateF, 'Last Reset': dateF,
    'Strike': numF, 'NDX_Strike': numF, 'RUT_Strike': numF,
  };

  final headStyle = CellStyle(
    bold: true,
    fontColorHex: ExcelColor.fromHexString('FFFFFFFF'),
    backgroundColorHex: ExcelColor.fromHexString('FF1F3A5F'),
    horizontalAlign: HorizontalAlign.Center,
    verticalAlign: VerticalAlign.Center,
    textWrapping: TextWrapping.WrapText,
  );
  // Tiger striping: alternate rows get a light-blue fill; the TOTAL row a tint.
  final stripeFill = ExcelColor.fromHexString('FFEAF1FB');
  final totalFill = ExcelColor.fromHexString('FFD7E3F4');

  CellStyle bodyStyle(NumFormat f, {bool bold = false, ExcelColor? fill}) =>
      CellStyle(
        numberFormat: f,
        bold: bold,
        backgroundColorHex: fill ?? ExcelColor.none,
      );

  for (var c = 0; c < headers.length; c++) {
    final name = headers[c];
    final f = byHeader[name] ?? NumFormat.standard_0;
    s.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: headerRowIdx))
        .cellStyle = headStyle;
    for (var r = headerRowIdx + 1; r <= totalRowIdx; r++) {
      final isTotal = r == totalRowIdx;
      final dataIdx = r - (headerRowIdx + 1);
      final fill = isTotal
          ? totalFill
          : (dataIdx.isOdd ? stripeFill : null);
      s.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r)).cellStyle =
          bodyStyle(f, bold: isTotal, fill: fill);
    }
    s.setColumnWidth(c, _xlsxColWidth(name));
  }
}

double _xlsxColWidth(String name) => switch (name) {
      'Position' => 24,
      'Index' => 15,
      'Issuer' || 'Type' => 12,
      'Proj Value @ Reset (\$000)' || 'Proj \$ Gain @ Reset (\$000)' => 15,
      'Initial (\$000)' || 'Realized (\$000)' => 13,
      'Floor Type' || 'Reset Freq' || 'Days to Maturity' || 'Days to Reset' => 12,
      'Next Reset' || 'Maturity' || 'Open' || 'Last Reset' => 11,
      'CAP' || 'Part.' || 'Floor' => 9,
      _ => 11,
    };
