// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: LicenseRef-Proprietary
// A polished, shareable .xlsx *report* — distinct from the raw round-trip
// tracker export (writeTracker). Reader-friendly: a branded title + owner line,
// a summary band, holdings grouped by account with subtotals + a grand total,
// friendly index names, plain protection, full dollars, and a disclaimer.
// Not re-importable by design — it's for showing people, not round-tripping.

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:xml/xml.dart';

import '../core/models.dart';
import '../core/payoff.dart' show FloorType;
import 'xirr.dart';

const _navy = 'FF1F3A5F';
const _white = 'FFFFFFFF';
const _stripe = 'FFEFF4FB';
const _groupFill = 'FFD7E3F4';
const _totalFill = 'FFBBD0EC';

/// One report column: header + width + number format (null = text).
class _RCol {
  const _RCol(this.label, this.width, [this.fmt]);
  final String label;
  final double width;
  final NumFormat? fmt;
}

NumFormat get _cur => CustomNumericNumFormat(formatCode: '\$#,##0');
NumFormat get _pctF => NumFormat.standard_10; // 0.00%
NumFormat get _numF => NumFormat.standard_4; // #,##0.00
NumFormat get _dateF => NumFormat.standard_15; // d-mmm-yy

// Grouped by account, so Account isn't repeated per row (it's the group band).
// Order: identity/terms → money → performance → dates/strike last.
List<_RCol> _cols() => [
      _RCol('Issuer', 20),
      _RCol('Index', 17),
      _RCol('Protection', 15),
      _RCol('Cap', 11, _pctF),
      _RCol('Participation', 13, _pctF),
      _RCol('Principal', 14, _cur),
      _RCol('Realized', 13, _cur),
      _RCol('Unrealized \$', 14, _cur),
      _RCol('Projected Value', 15, _cur),
      _RCol('Index Gain', 11, _pctF),
      _RCol('Return %', 10, _pctF),
      _RCol('Yield', 10, _pctF),
      _RCol('Strike', 11, _numF),
      _RCol('Maturity', 12, _dateF),
      _RCol('Next Reset', 12, _dateF),
    ];

const _iCap = 3, _iPart = 4;
const _iPrincipal = 5, _iRealized = 6, _iUnrealized = 7, _iProjValue = 8;
const _iIndexGain = 9, _iReturn = 10, _iYield = 11;
const _iStrike = 12, _iMaturity = 13, _iReset = 14;

String _friendlyIndex(String index) {
  if (index.contains('/')) {
    final legs = index.replaceFirst(
        RegExp(r'^\s*worst[- ]of\s+', caseSensitive: false), '');
    return 'Worst-of $legs';
  }
  return switch (index.toUpperCase().replaceAll('^', '')) {
    'GSPC' || 'SPX' => 'S&P 500',
    'NDX' => 'Nasdaq-100',
    'RUT' => 'Russell 2000',
    'DJI' => 'Dow Jones',
    'IXIC' || 'COMP' => 'Nasdaq Composite',
    _ => index,
  };
}

String _pctText(double v) => '${(v * 100).toStringAsFixed(2)}%';
String _protection(Holding h) =>
    h.floorType == FloorType.none ? 'None' : '${h.protectionType} ${_pctText(h.floor)}';

/// Money-weighted XIRR for a set of holdings (same convention as the app).
double? _xirr(List<Holding> items, DateTime asOf) {
  if (items.isEmpty) return null;
  final proj = items.fold(0.0, (s, h) => s + h.projValueK);
  return xirr([
    for (final h in items) (h.returnStart, -h.initial),
    (asOf, proj),
  ]);
}

/// Build the shareable report workbook. [holdings] must already be in the order
/// to display (the caller passes the table's current sort). When [groupBy] is
/// non-empty, holdings are grouped by [groupValueOf] in first-appearance order
/// (matching the on-screen pivot) with a subtotal band per group; otherwise the
/// report is a flat sorted list. Either way it ends with a grand total.
List<int> writeReport(
  List<Holding> holdings, {
  required DateTime asOf,
  required DateTime generatedOn,
  String? preparedFor,
  String groupBy = '',
  String Function(Holding)? groupValueOf,
}) {
  final excel = Excel.createExcel();
  const sheetName = 'Portfolio Report';
  final def = excel.getDefaultSheet();
  if (def != null && def != sheetName) excel.rename(def, sheetName);
  final s = excel[sheetName];
  final cols = _cols();
  final lastCol = cols.length - 1;

  // Reusable styles.
  final titleStyle = CellStyle(
      bold: true,
      fontSize: 18,
      fontColorHex: ExcelColor.fromHexString(_white),
      backgroundColorHex: ExcelColor.fromHexString(_navy),
      verticalAlign: VerticalAlign.Center);
  final subStyle = CellStyle(
      italic: true,
      fontColorHex: ExcelColor.fromHexString(_white),
      backgroundColorHex: ExcelColor.fromHexString(_navy));
  final sectionStyle = CellStyle(
      bold: true, fontColorHex: ExcelColor.fromHexString(_navy), fontSize: 12);
  final headStyle = CellStyle(
      bold: true,
      fontColorHex: ExcelColor.fromHexString(_white),
      backgroundColorHex: ExcelColor.fromHexString(_navy),
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
      textWrapping: TextWrapping.WrapText);
  final discStyle = CellStyle(
      italic: true,
      fontSize: 10, // no text below 10pt
      fontColorHex: ExcelColor.fromHexString('FF555555'),
      textWrapping: TextWrapping.WrapText);

  var row = 0;
  void put(int col, int r, CellValue? v, {CellStyle? style}) {
    final cell = s.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: r));
    if (v != null) cell.value = v;
    if (style != null) cell.cellStyle = style;
  }

  void mergedLine(String text, CellStyle style, {double? height}) {
    put(0, row, TextCellValue(text), style: style);
    for (var c = 1; c <= lastCol; c++) {
      put(c, row, null, style: style);
    }
    s.merge(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
        CellIndex.indexByColumnRow(columnIndex: lastCol, rowIndex: row));
    if (height != null) s.setRowHeight(row, height);
    row++;
  }

  // ---- Title + owner + as-of ----
  mergedLine('iHaveAnnuities — Portfolio Report', titleStyle, height: 28);
  if (preparedFor != null && preparedFor.trim().isNotEmpty) {
    mergedLine('Prepared for ${preparedFor.trim()}', subStyle);
  }
  mergedLine(
      'As of ${_d(asOf)}   ·   Generated ${_d(generatedOn)}   ·   ${holdings.length} contracts',
      subStyle);
  row++; // spacer

  // ---- Summary band ----
  final totInit = holdings.fold(0.0, (a, h) => a + h.initial);
  final totReal = holdings.fold(0.0, (a, h) => a + h.realized);
  final totProj = holdings.fold(0.0, (a, h) => a + h.projValueK);
  final totUnreal = totProj - totInit - totReal;
  final xirrAll = _xirr(holdings, asOf);
  final mix = <String, double>{};
  for (final h in holdings) {
    mix[h.protectionType] = (mix[h.protectionType] ?? 0) + h.initial;
  }
  final mixText = (mix.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value)))
      .map((e) => '${e.key} ${totInit <= 0 ? 0 : (e.value / totInit * 100).round()}%')
      .join('  ·  ');

  put(0, row, TextCellValue('SUMMARY'), style: sectionStyle);
  row++;
  // A summary line: label | value | (real %) | qualifier text. The percentage
  // is a true number with a % format — never text — so Excel doesn't flag it.
  void kv(String k, CellValue v, {NumFormat? fmt, double? pct, String? qualifier}) {
    put(0, row, TextCellValue(k),
        style: CellStyle(bold: true, fontColorHex: ExcelColor.fromHexString('FF444444')));
    put(1, row, v, style: CellStyle(numberFormat: fmt ?? NumFormat.standard_0, bold: true));
    if (pct != null) {
      put(2, row, DoubleCellValue(pct), style: CellStyle(numberFormat: _pctF, bold: true));
    }
    if (qualifier != null) put(3, row, TextCellValue(qualifier));
    row++;
  }

  kv('Total Value', DoubleCellValue(totProj * 1000),
      fmt: _cur, pct: xirrAll, qualifier: xirrAll != null ? '/ yr (XIRR)' : null);
  kv('Principal', DoubleCellValue(totInit * 1000), fmt: _cur);
  kv('Realized', DoubleCellValue(totReal * 1000), fmt: _cur);
  kv('Unrealized', DoubleCellValue(totUnreal * 1000),
      fmt: _cur,
      pct: totInit <= 0 ? null : totUnreal / totInit,
      qualifier: totInit <= 0 ? null : 'of principal');
  kv('Protection mix', TextCellValue(mixText));
  row++; // spacer

  // ---- Holdings header ----
  final headerRow = row;
  for (var c = 0; c <= lastCol; c++) {
    put(c, headerRow, TextCellValue(cols[c].label), style: headStyle);
    s.setColumnWidth(c, cols[c].width);
  }
  row++;

  // ---- Grouped by account, band-first (name + subtotals), then members ----
  CellStyle cellStyle(NumFormat? f, {String? fill, HorizontalAlign? align}) =>
      CellStyle(
          numberFormat: f ?? NumFormat.standard_0,
          horizontalAlign: align ?? HorizontalAlign.Left,
          backgroundColorHex:
              fill == null ? ExcelColor.none : ExcelColor.fromHexString(fill));

  void aggregateRow(String label, List<Holding> items, {required bool grand}) {
    final init = items.fold(0.0, (a, h) => a + h.initial);
    final real = items.fold(0.0, (a, h) => a + h.realized);
    final proj = items.fold(0.0, (a, h) => a + h.projValueK);
    final unreal = proj - init - real;
    final idxW = init == 0
        ? 0.0
        : items.fold(0.0, (a, h) => a + h.indexGain * h.initial) / init;
    final fill = ExcelColor.fromHexString(grand ? _totalFill : _groupFill);
    CellStyle band({NumFormat? f}) => CellStyle(
        bold: true,
        numberFormat: f ?? NumFormat.standard_0,
        backgroundColorHex: fill);
    for (var c = 0; c <= lastCol; c++) {
      put(c, row, null, style: band());
    }
    put(0, row, TextCellValue(label), style: band());
    put(_iPrincipal, row, DoubleCellValue(init * 1000), style: band(f: _cur));
    put(_iRealized, row, DoubleCellValue(real * 1000), style: band(f: _cur));
    put(_iUnrealized, row, DoubleCellValue(unreal * 1000), style: band(f: _cur));
    put(_iProjValue, row, DoubleCellValue(proj * 1000), style: band(f: _cur));
    put(_iIndexGain, row, DoubleCellValue(idxW), style: band(f: _pctF));
    if (init != 0) {
      put(_iReturn, row, DoubleCellValue((proj - init) / init),
          style: band(f: _pctF));
    }
    final gx = _xirr(items, asOf);
    if (gx != null) {
      put(_iYield, row, DoubleCellValue(gx), style: band(f: _pctF));
    }
    row++;
  }

  // Track member rows (outline level 1) for the outline injected after encoding.
  final memberRows = <int>[];
  var dataIdx = 0;
  void member(Holding h) {
    final fill = dataIdx.isOdd ? _stripe : null;
    dataIdx++;
    put(0, row, TextCellValue(h.issuer), style: cellStyle(null, fill: fill));
    put(1, row, TextCellValue(_friendlyIndex(h.index)), style: cellStyle(null, fill: fill));
    put(2, row, TextCellValue(_protection(h)), style: cellStyle(null, fill: fill));
    put(_iCap, row,
        h.cap == null ? TextCellValue('Uncapped') : DoubleCellValue(h.cap!),
        style: cellStyle(h.cap == null ? null : _pctF,
            fill: fill, align: h.cap == null ? HorizontalAlign.Right : null));
    put(_iPart, row, DoubleCellValue(h.participation), style: cellStyle(_pctF, fill: fill));
    put(_iPrincipal, row, DoubleCellValue(h.initial * 1000), style: cellStyle(_cur, fill: fill));
    put(_iRealized, row, DoubleCellValue(h.realized * 1000), style: cellStyle(_cur, fill: fill));
    put(_iUnrealized, row, DoubleCellValue(h.projGainDollarsK * 1000), style: cellStyle(_cur, fill: fill));
    put(_iProjValue, row, DoubleCellValue(h.projValueK * 1000), style: cellStyle(_cur, fill: fill));
    put(_iIndexGain, row, DoubleCellValue(h.indexGain), style: cellStyle(_pctF, fill: fill));
    put(_iReturn, row, DoubleCellValue(h.totalReturnPct), style: cellStyle(_pctF, fill: fill));
    put(_iYield, row, DoubleCellValue(h.lifeToDateYield(asOf)), style: cellStyle(_pctF, fill: fill));
    put(_iStrike, row, DoubleCellValue(h.strike), style: cellStyle(_numF, fill: fill));
    put(_iMaturity, row, _date(h.maturity), style: cellStyle(_dateF, fill: fill));
    put(_iReset, row, _date(h.nextReset), style: cellStyle(_dateF, fill: fill));
    row++;
  }

  if (groupBy.isNotEmpty && groupValueOf != null) {
    // Group by the on-screen dimension, in first-appearance order (holdings are
    // already in the table's sort order). Each group: band + members.
    final groups = <String, List<Holding>>{};
    for (final h in holdings) {
      (groups[groupValueOf(h)] ??= []).add(h);
    }
    groups.forEach((value, items) {
      aggregateRow('$value  (${items.length})', items, grand: false);
      for (final h in items) {
        memberRows.add(row);
        member(h);
      }
    });
  } else {
    // Ungrouped: a flat list in the table's sort order (no bands, no outline).
    for (final h in holdings) {
      member(h);
    }
  }
  aggregateRow('TOTAL', holdings, grand: true);
  row++; // spacer

  // ---- Disclaimer ----
  for (final line in const [
    'Illustrative estimates, not investment advice. Figures are projected at each '
        'contract\'s next reset using current index levels and will differ from '
        'actual values. Rely on your official statements, prospectus, and contract.',
    'Any protection or floor is backed solely by the claims-paying ability of the '
        'issuing insurer. Not affiliated with or endorsed by any insurer or index provider.',
  ]) {
    mergedLine(line, discStyle, height: 30);
  }

  return _applyRowOutline(excel.encode()!, memberRows, headerRow);
}

/// Post-process the encoded .xlsx (a zip) to add two things the `excel` package
/// can't emit: a native row outline (groups collapse/expand via the ± buttons;
/// outlineLevel 1, summaryBelow=0 → band above, starts expanded) and a freeze
/// that keeps columns A–F and everything through the header row ([headerRow0],
/// 0-based) on screen while scrolling. Best-effort: input unchanged on any hiccup.
List<int> _applyRowOutline(List<int> bytes, List<int> memberRows0, int headerRow0) {
  try {
    final members = {for (final r in memberRows0) r + 1}; // xlsx rows are 1-based
    final archive = ZipDecoder().decodeBytes(bytes);
    final ws = archive.files.firstWhere(
        (f) => f.name.contains('worksheets/') && f.name.endsWith('.xml'));
    final doc = XmlDocument.parse(utf8.decode(ws.content as List<int>));
    final root = doc.rootElement;

    // <sheetPr><outlinePr summaryBelow="0"/></sheetPr> as the first child.
    var sheetPr = root.childElements
        .where((e) => e.name.local == 'sheetPr')
        .cast<XmlElement?>()
        .firstWhere((_) => true, orElse: () => null);
    if (sheetPr == null) {
      sheetPr = XmlElement(XmlName('sheetPr'));
      root.children.insert(0, sheetPr);
    }
    if (!sheetPr.childElements.any((e) => e.name.local == 'outlinePr')) {
      sheetPr.children.insert(
          0,
          XmlElement(XmlName('outlinePr'), [
            XmlAttribute(XmlName('summaryBelow'), '0'),
            XmlAttribute(XmlName('summaryRight'), '0'),
          ]));
    }

    for (final rowEl in doc.descendantElements.where((e) => e.name.local == 'row')) {
      final r = int.tryParse(rowEl.getAttribute('r') ?? '');
      if (r != null && members.contains(r)) {
        rowEl.setAttribute('outlineLevel', '1'); // grouped; starts expanded
      }
    }

    // Freeze columns A–F and every row through the header (split just below it)
    // so the title/summary/header and the identity columns stay visible.
    final frozenRows = headerRow0 + 1; // 1-based count of rows to freeze
    final topLeft = 'G${headerRow0 + 2}'; // first scrollable cell
    final views = doc.descendantElements
        .where((e) => e.name.local == 'sheetView')
        .cast<XmlElement?>()
        .firstWhere((_) => true, orElse: () => null);
    if (views != null && !views.childElements.any((e) => e.name.local == 'pane')) {
      views.children.insert(
          0,
          XmlElement(XmlName('pane'), [
            XmlAttribute(XmlName('xSplit'), '6'),
            XmlAttribute(XmlName('ySplit'), '$frozenRows'),
            XmlAttribute(XmlName('topLeftCell'), topLeft),
            XmlAttribute(XmlName('activePane'), 'bottomRight'),
            XmlAttribute(XmlName('state'), 'frozen'),
          ]));
    }

    final newBytes = utf8.encode(doc.toXmlString());
    final out = Archive();
    for (final f in archive.files) {
      out.addFile(identical(f, ws)
          ? ArchiveFile(f.name, newBytes.length, newBytes)
          : f);
    }
    return ZipEncoder().encode(out) ?? bytes;
  } catch (_) {
    return bytes; // never fail the export over cosmetics
  }
}

CellValue _date(DateTime d) =>
    DateCellValue(year: d.year, month: d.month, day: d.day);
String _d(DateTime d) {
  const m = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  return '${d.day}-${m[d.month - 1]}-${d.year}';
}
