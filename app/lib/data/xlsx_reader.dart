//
//  xlsx_reader.dart
//  iHaveAnnuities
//
//  Copyright 2026 Jim Zucker
//  SPDX-License-Identifier: Apache-2.0
//
// Minimal, robust read-only .xlsx decoder. Unlike the off-the-shelf packages it
// handles BOTH shared strings and inline strings (which real Excel/Numbers files
// often use) and converts Excel date serials to DateTime. Returns each sheet as
// a grid of plain values (String / num / bool / DateTime / null).

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

class XlsxReader {
  /// sheet name -> rows -> cells (column-aligned; gaps are null).
  static Map<String, List<List<dynamic>>> decode(List<int> bytes) {
    final arch = ZipDecoder().decodeBytes(bytes);
    final files = <String, ArchiveFile>{for (final f in arch.files) f.name: f};
    String text(String name) =>
        utf8.decode((files[name]!.content as List<int>), allowMalformed: true);

    final shared = <String>[];
    if (files.containsKey('xl/sharedStrings.xml')) {
      for (final si in XmlDocument.parse(text('xl/sharedStrings.xml'))
          .findAllElements('si')) {
        shared.add(_siText(si));
      }
    }

    final dateStyle = _dateStyleFlags(files.containsKey('xl/styles.xml')
        ? XmlDocument.parse(text('xl/styles.xml'))
        : null);

    // Map sheet name -> worksheet path via workbook rels.
    final rels = <String, String>{};
    if (files.containsKey('xl/_rels/workbook.xml.rels')) {
      for (final r in XmlDocument.parse(text('xl/_rels/workbook.xml.rels'))
          .findAllElements('Relationship')) {
        rels[r.getAttribute('Id') ?? ''] = r.getAttribute('Target') ?? '';
      }
    }

    final out = <String, List<List<dynamic>>>{};
    final wb = XmlDocument.parse(text('xl/workbook.xml'));
    var fallback = 1;
    for (final sheet in wb.findAllElements('sheet')) {
      final name = sheet.getAttribute('name') ?? 'Sheet$fallback';
      final rid = sheet.getAttribute('r:id') ?? sheet.getAttribute('id');
      var target = rels[rid] ?? 'worksheets/sheet${fallback++}.xml';
      target = target.replaceFirst('/xl/', '').replaceFirst(RegExp(r'^/'), '');
      final path = target.startsWith('xl/') ? target : 'xl/$target';
      if (!files.containsKey(path)) continue;
      out[name] = _parseSheet(text(path), shared, dateStyle);
    }
    return out;
  }

  static String _siText(XmlElement si) =>
      si.findAllElements('t').map((t) => t.innerText).join();

  /// cellXfs index -> is-a-date-format.
  static List<bool> _dateStyleFlags(XmlDocument? styles) {
    if (styles == null) return const [];
    final custom = <int, bool>{};
    for (final n in styles.findAllElements('numFmt')) {
      final id = int.tryParse(n.getAttribute('numFmtId') ?? '');
      final code = (n.getAttribute('formatCode') ?? '').toLowerCase();
      if (id != null) {
        custom[id] = RegExp(r'[dy]').hasMatch(code) ||
            (code.contains('m') && !code.contains(r'$') && !code.contains('%'));
      }
    }
    bool isDateId(int id) =>
        (id >= 14 && id <= 22) || (id >= 45 && id <= 47) || (custom[id] ?? false);
    final flags = <bool>[];
    final cellXfs = styles.findAllElements('cellXfs').firstOrNull;
    if (cellXfs == null) return flags;
    for (final xf in cellXfs.findElements('xf')) {
      final id = int.tryParse(xf.getAttribute('numFmtId') ?? '0') ?? 0;
      flags.add(isDateId(id));
    }
    return flags;
  }

  static List<List<dynamic>> _parseSheet(
      String xml, List<String> shared, List<bool> dateStyle) {
    final doc = XmlDocument.parse(xml);
    final rows = <List<dynamic>>[];
    for (final row in doc.findAllElements('row')) {
      final cells = <int, dynamic>{};
      var maxCol = -1;
      for (final c in row.findElements('c')) {
        final ref = c.getAttribute('r') ?? '';
        final col = _colIndex(ref);
        final t = c.getAttribute('t');
        final s = int.tryParse(c.getAttribute('s') ?? '');
        dynamic value;
        if (t == 'inlineStr') {
          value = c.findElements('is').map(_siText).join();
        } else {
          final v = c.findElements('v').firstOrNull?.innerText;
          if (v == null || v.isEmpty) {
            value = null;
          } else if (t == 's') {
            value = shared[int.parse(v)];
          } else if (t == 'str') {
            value = v;
          } else if (t == 'b') {
            value = v == '1';
          } else if (t == 'e') {
            value = null; // error cell
          } else {
            final num n = num.parse(v);
            final isDate = s != null && s < dateStyle.length && dateStyle[s];
            value = isDate ? _excelDate(n.toDouble()) : n;
          }
        }
        cells[col] = value;
        if (col > maxCol) maxCol = col;
      }
      final list = List<dynamic>.filled(maxCol + 1, null);
      cells.forEach((k, v) => list[k] = v);
      rows.add(list);
    }
    return rows;
  }

  /// "B3" -> 1 (zero-based column index).
  static int _colIndex(String ref) {
    var i = 0, col = 0;
    while (i < ref.length && ref.codeUnitAt(i) >= 65 && ref.codeUnitAt(i) <= 90) {
      col = col * 26 + (ref.codeUnitAt(i) - 64);
      i++;
    }
    return col - 1;
  }

  /// Excel 1900 date system (with the 1900 leap-year bug): serial → DateTime.
  static DateTime _excelDate(double serial) =>
      DateTime(1899, 12, 30).add(Duration(days: serial.floor()));
}
