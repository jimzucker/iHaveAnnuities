// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: Apache-2.0
// Import the generated example, round-trip, and import the real tracker.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ihaveannuities/core/models.dart';
import 'package:ihaveannuities/core/payoff.dart';
import 'package:ihaveannuities/data/tracker_xlsx.dart';
import 'package:ihaveannuities/data/xlsx_reader.dart';

void main() {
  final examplePath = '../data/example-portfolio.xlsx';
  final realPath = '${Platform.environment['HOME']}/Library/Mobile Documents/'
      'com~apple~CloudDocs/jim-icloud-drive/claude-files/Zucker-Annuity-Tracker.xlsx';

  test('parses the generated example-portfolio.xlsx (8 holdings)', () {
    final holdings = parseTracker(File(examplePath).readAsBytesSync());
    expect(holdings.length, 8);

    final aspida = holdings.firstWhere((h) => h.issuer == 'ASPIDA');
    expect(aspida.cap, closeTo(0.1225, 1e-9));
    expect(aspida.floor, 0.0);
    expect(aspida.floorType, FloorType.hard);
    expect(aspida.protectionType, 'Protected');
    expect(aspida.account, AccountType.nonQual);
    expect(aspida.position, 'ASPIDA-0%-14Nov28'); // computed name, uppercase
    expect(aspida.projGain, closeTo(0.1225, 1e-6)); // recomputed from strike/gain
    expect(aspida.projValueK, closeTo(112.25, 1e-3));

    final bnp = holdings.firstWhere((h) => h.issuer == 'BNP');
    expect(bnp.cap, isNull); // 9.99 sentinel → uncapped
    expect(bnp.floorType, FloorType.soft);
    expect(bnp.participation, closeTo(1.05, 1e-9));
    expect(bnp.projValueK, closeTo(65.0, 1e-2)); // -35% breaches -30% soft

    final note = holdings.firstWhere((h) => h.isIncomeNote);
    expect(note.resetFreq, ResetFreq.monthly);
    expect(note.index, 'SPX/NDX/RUT'); // v1.0 worst-of label
    expect(note.ndxStrike, 27290);     // worst-of strikes round-trip
    expect(note.rutStrike, 2719);
    // Tracker formula: gain = (initial + realized) * projGain; and the identity
    // value = initial + realized + gain holds.
    expect(note.realized, closeTo(1.10, 1e-9));
    expect(note.projGainDollarsK,
        closeTo((note.initial + note.realized) * note.projGain, 1e-9));
    expect(note.initial + note.realized + note.projGainDollarsK,
        closeTo(note.projValueK, 1e-6));
  });

  test('exports the v1.2 column order (identity → inputs → outcome → …)', () {
    final original = parseTracker(File(examplePath).readAsBytesSync());
    final bytes = writeTracker(original,
        asOf: DateTime(2026, 6, 14),
        prices: {'SPX': 7400, 'NDX': 29600, 'RUT': 2950});
    final rows = XlsxReader.decode(bytes)['Annuity Tracker']!;
    final headerRow = rows.firstWhere(
        (r) => r.any((c) => c?.toString().trim() == 'Issuer'));
    final names = headerRow
        .map((c) => c?.toString().trim())
        .where((s) => s != null && s.isNotEmpty)
        .toList();
    expect(names, headers); // full v1.2 order
    // identity leads; Initial sits next to Proj Value; timing before terms.
    expect(names.take(9).toList(), [
      'Position', 'Issuer', 'Type', 'Index', 'Floor Type',
      'Initial (\$000)', 'Realized (\$000)',
      'Proj Value @ Reset (\$000)', 'Proj \$ Gain @ Reset (\$000)',
    ]);
    // monitor dates precede the static terms.
    expect(names.indexOf('Next Reset'), lessThan(names.indexOf('CAP')));
    // a styled TOTAL row is appended (and skipped on re-import).
    final totalRow = rows.firstWhere(
        (r) => r.isNotEmpty && r.first?.toString().trim() == 'TOTAL');
    expect(totalRow[7], closeTo(851.98, 0.02)); // Proj Value total (col H)
  });

  test('gainStatus flags capped / loss / gain', () {
    final hs = parseTracker(File(examplePath).readAsBytesSync());
    // +18% index vs a 12.25% cap → ceilinged.
    expect(hs.firstWhere((h) => h.issuer == 'ASPIDA').gainStatus,
        GainStatus.capped);
    // −35% breaches the −30% soft barrier → full loss.
    expect(hs.firstWhere((h) => h.issuer == 'BNP').gainStatus, GainStatus.loss);
    // uncapped +40% at 92.25% participation → gain with no ceiling.
    expect(hs.firstWhere((h) => h.issuer == 'HSBC').gainStatus, GainStatus.gain);
  });

  test('downloadable template.xlsx is valid + parseable', () {
    final holdings = parseTracker(File('../data/template.xlsx').readAsBytesSync());
    expect(holdings, isNotEmpty); // sample rows present
    for (final h in holdings) {
      expect(h.position, isNotEmpty);
    }
  });

  test('round-trips: write -> read preserves inputs', () {
    final original = parseTracker(File(examplePath).readAsBytesSync());
    final bytes = writeTracker(original,
        asOf: DateTime(2026, 6, 14),
        prices: {'SPX': 7400, 'NDX': 29600, 'RUT': 2950});
    final reparsed = parseTracker(bytes);

    expect(reparsed.length, original.length);
    for (var i = 0; i < original.length; i++) {
      final a = original[i], b = reparsed[i];
      expect(b.position, a.position);
      expect(b.cap ?? -1, closeTo(a.cap ?? -1, 1e-9));
      expect(b.participation, closeTo(a.participation, 1e-9));
      expect(b.floor, closeTo(a.floor, 1e-9));
      expect(b.floorType, a.floorType);
      expect(b.account, a.account);
      expect(b.resetFreq, a.resetFreq);
      expect(b.initial, closeTo(a.initial, 1e-9));
      expect(b.maturity, a.maturity);
      expect(b.projValueK, closeTo(a.projValueK, 1e-6));
    }
  });

  test('imports the real Zucker-Annuity-Tracker.xlsx', () {
    final f = File(realPath);
    if (!f.existsSync()) {
      markTestSkipped('real tracker not present at $realPath');
      return;
    }
    final holdings = parseTracker(f.readAsBytesSync());
    expect(holdings.length, greaterThan(10));
    // Every parsed holding has a usable name and a positive strike.
    for (final h in holdings) {
      expect(h.position, isNotEmpty);
      expect(h.strike, greaterThan(0));
    }
    expect(holdings.any((h) => h.issuer.toUpperCase().contains('AIG')), isTrue);
  });
}
