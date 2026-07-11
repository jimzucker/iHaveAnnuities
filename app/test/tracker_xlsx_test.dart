// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: LicenseRef-Proprietary
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

  test('parses the generated example-portfolio.xlsx (9 holdings)', () {
    final holdings = parseTracker(File(examplePath).readAsBytesSync());
    expect(holdings.length, 9);

    final aspida = holdings.firstWhere((h) => h.issuer == 'ASPIDA');
    expect(aspida.cap, closeTo(0.1225, 1e-9));
    expect(aspida.floor, 0.0);
    // 0% floor now exports as "Floor" and re-imports as FloorType.floor;
    // either way protectionType is "Floor" because floor == 0.
    expect(aspida.floorType, FloorType.floor);
    expect(aspida.protectionType, 'Floor');

    // The max-loss Floor example imports as FloorType.floor.
    final marex = holdings.firstWhere((h) => h.issuer == 'MAREX');
    expect(marex.floorType, FloorType.floor);
    expect(marex.protectionType, 'Floor');
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
    expect(totalRow[7], closeTo(941.98, 0.02)); // Proj Value total (col H)
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

  test('Inception column round-trips and is back-compatible', () {
    final base = parseTracker(File(examplePath).readAsBytesSync());
    // Existing files have no Inception column → null (falls back to Open).
    expect(base.first.inceptionDate, isNull);

    final h0 = base.first;
    final seeded = [
      Holding(
        issuer: h0.issuer, index: h0.index, account: h0.account, cap: h0.cap,
        participation: h0.participation, floor: h0.floor, floorType: h0.floorType,
        strike: h0.strike, currentLevel: h0.currentLevel, openDate: h0.openDate,
        lastReset: h0.lastReset, maturity: h0.maturity, nextReset: h0.nextReset,
        resetFreq: h0.resetFreq, initial: h0.initial, realized: h0.realized,
        inceptionDate: DateTime(2019, 5, 20),
      ),
      ...base.skip(1),
    ];
    final bytes = writeTracker(seeded,
        asOf: DateTime(2026, 6, 14), prices: {'SPX': 7400, 'NDX': 29600, 'RUT': 2950});
    final reparsed = parseTracker(bytes);
    final back = reparsed.first.inceptionDate!;
    expect([back.year, back.month, back.day], [2019, 5, 20]); // same calendar day
    expect(reparsed[1].inceptionDate, isNull); // others stay null
  });

  test('None protection round-trips as "None"', () {
    final base = parseTracker(File(examplePath).readAsBytesSync());
    final h0 = base.first;
    final none = Holding(
      issuer: h0.issuer, index: h0.index, account: h0.account, cap: h0.cap,
      participation: h0.participation, floor: 0.0, floorType: FloorType.none,
      strike: h0.strike, currentLevel: h0.currentLevel, openDate: h0.openDate,
      lastReset: h0.lastReset, maturity: h0.maturity, nextReset: h0.nextReset,
      resetFreq: h0.resetFreq, initial: h0.initial, realized: h0.realized,
    );
    expect(none.protectionType, 'None'); // Floor Type cell exports as "None"
    final bytes = writeTracker([none],
        asOf: DateTime(2026, 6, 14), prices: {'SPX': 7400, 'NDX': 29600, 'RUT': 2950});
    final reparsed = parseTracker(bytes).first;
    expect(reparsed.floorType, FloorType.none);
    expect(reparsed.protectionType, 'None');
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
