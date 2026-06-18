// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: Apache-2.0
// Holding derived-value coverage, mirroring the eight example contracts.

import 'package:flutter_test/flutter_test.dart';
import 'package:ihaveannuities/core/models.dart';
import 'package:ihaveannuities/core/payoff.dart';

Holding _h({
  double? cap,
  double participation = 1.0,
  required double floor,
  FloorType floorType = FloorType.hard,
  required double strike,
  required double currentLevel,
  double initial = 100.0,
  double realized = 0.0,
  bool isIncomeNote = false,
  double couponProj = 0.0,
}) {
  final d = DateTime(2026, 1, 1);
  return Holding(
    issuer: 'x',
    index: 'SPX',
    account: AccountType.nonQual,
    cap: cap,
    participation: participation,
    floor: floor,
    floorType: floorType,
    strike: strike,
    currentLevel: currentLevel,
    openDate: d,
    lastReset: d,
    maturity: DateTime(2030, 1, 1),
    nextReset: DateTime(2027, 1, 1),
    resetFreq: ResetFreq.annual,
    initial: initial,
    realized: realized,
    isIncomeNote: isIncomeNote,
    couponProj: couponProj,
  );
}

void main() {
  test('Aspida: +18% capped at 12.25% -> \$112.25k', () {
    final h = _h(cap: 0.1225, floor: 0, strike: 100, currentLevel: 118);
    expect(h.projGain, closeTo(0.1225, 1e-12));
    expect(h.projValueK, closeTo(112.25, 1e-9));
  });

  test('Axa 65%: -22% with -15% hard buffer -> -7% -> \$93k', () {
    final h = _h(cap: 0.65, floor: -0.15, strike: 100, currentLevel: 78);
    expect(h.projGain, closeTo(-0.07, 1e-12));
    expect(h.projValueK, closeTo(93.0, 1e-9));
  });

  test('Citi IRA: +30% uncapped @102% -> +30.6% -> \$130.6k', () {
    final h = _h(
        cap: null, participation: 1.02, floor: -0.15, strike: 100, currentLevel: 130);
    expect(h.projGain, closeTo(0.306, 1e-12));
    expect(h.projValueK, closeTo(130.6, 1e-9));
  });

  test('HSBC: +40% uncapped @92.25% -> +36.9% -> \$136.9k', () {
    final h = _h(
        cap: null, participation: 0.9225, floor: -0.15, strike: 100, currentLevel: 140);
    expect(h.projGain, closeTo(0.369, 1e-12));
    expect(h.projValueK, closeTo(136.9, 1e-9));
  });

  test('BNP: -35% breaches -30% soft barrier -> -35% -> \$65k', () {
    final h = _h(
        cap: null,
        participation: 1.05,
        floor: -0.30,
        floorType: FloorType.soft,
        strike: 100,
        currentLevel: 65);
    expect(h.projGain, closeTo(-0.35, 1e-12));
    expect(h.projValueK, closeTo(65.0, 1e-9));
  });

  test('Income note: coupon = cap/12, projection + realized', () {
    final h = _h(
        cap: 0.1325,
        floor: -0.30,
        floorType: FloorType.soft,
        strike: 6583,
        currentLevel: 7140,
        realized: 1.10,
        isIncomeNote: true,
        couponProj: 0.0112); // stored value ignored; coupon derives from cap/12
    // Coupon = annual cap / 12 = 13.25% / 12 = 1.104% (matches the reset engine).
    expect(h.couponRate, closeTo(0.1325 / 12, 1e-12));
    expect(h.projGain, closeTo(0.1325 / 12, 1e-12));
    // (initial + realized) * (1 + cap/12) = 101.10 * 1.0110417.
    expect(h.projValueK, closeTo(102.2163, 1e-3));
    expect(h.initial + h.realized + h.projGainDollarsK,
        closeTo(h.projValueK, 1e-6));
  });

  test('Income note without a cap falls back to stored couponProj', () {
    final h = _h(
        cap: null,
        floor: -0.30,
        strike: 6583,
        currentLevel: 7140,
        isIncomeNote: true,
        couponProj: 0.0112);
    expect(h.couponRate, closeTo(0.0112, 1e-12));
  });

  test('Axa 100%: -15% within -20% buffer -> 0% -> \$100k', () {
    final h = _h(cap: 1.0, floor: -0.20, strike: 100, currentLevel: 85);
    expect(h.projGain, 0.0);
    expect(h.projValueK, closeTo(100.0, 1e-9));
  });

  test('projValue reinvests realized — on gains AND losses', () {
    // gain: (100 + 20) * (1 + 0.10) = 132.0; unrealized = 120 * 0.10 = 12.0
    final g = _h(cap: null, floor: 0, strike: 100, currentLevel: 110, realized: 20);
    expect(g.projValueK, closeTo(132.0, 1e-9));
    expect(g.projGainDollarsK, closeTo(12.0, 1e-9));
    expect(g.initial + g.realized + g.projGainDollarsK, closeTo(g.projValueK, 1e-9));
    // loss: (100 + 10) * (1 + -0.07) = 102.30; unrealized = 110 * -0.07 = -7.70
    final l = _h(
        cap: null, floor: -0.05, floorType: FloorType.hard,
        strike: 100, currentLevel: 88, realized: 10); // -12% beyond -5% buffer => -7%
    expect(l.projGain, closeTo(-0.07, 1e-9));
    expect(l.projValueK, closeTo(102.30, 1e-9));
    expect(l.projGainDollarsK, closeTo(-7.70, 1e-9));
  });

  test('gainStatus + hasCap across loss / flat / gain / capped', () {
    // capped: +20% vs a 10% cap
    final capped = _h(cap: 0.10, floor: 0, strike: 100, currentLevel: 120);
    expect(capped.gainStatus, GainStatus.capped);
    expect(capped.hasCap, isTrue);
    // gain with room left (capped product, below the cap)
    expect(_h(cap: 0.30, floor: 0, strike: 100, currentLevel: 110).gainStatus,
        GainStatus.gain);
    // gain uncapped
    final unc = _h(cap: null, floor: 0, strike: 100, currentLevel: 110);
    expect(unc.gainStatus, GainStatus.gain);
    expect(unc.hasCap, isFalse);
    // flat: -10% sits within a -20% buffer => 0%
    expect(
        _h(cap: 0.10, floor: -0.20, floorType: FloorType.hard, strike: 100, currentLevel: 90)
            .gainStatus,
        GainStatus.flat);
    // loss: -20% beyond a -10% buffer => -10%
    expect(
        _h(cap: 0.10, floor: -0.10, floorType: FloorType.hard, strike: 100, currentLevel: 80)
            .gainStatus,
        GainStatus.loss);
  });

  test('protectionType: Floor / Hard-buffer / Soft-buffer', () {
    // 0% floor folds into "Floor".
    expect(_h(cap: null, floor: 0, strike: 100, currentLevel: 100).protectionType,
        'Floor');
    expect(_h(cap: null, floor: -0.10, strike: 100, currentLevel: 100).protectionType,
        'Hard-buffer');
    expect(
        _h(cap: null, floor: -0.30, floorType: FloorType.soft, strike: 100, currentLevel: 100)
            .protectionType,
        'Soft-buffer');
    expect(
        _h(cap: null, floor: -0.15, floorType: FloorType.floor, strike: 100, currentLevel: 100)
            .protectionType,
        'Floor');
  });

  test('computed position = ISSUER-floor-maturity (issuer uppercased)', () {
    expect(_h(cap: 0.1225, floor: 0, strike: 100, currentLevel: 118).position,
        'X-0%-01Jan30');
    expect(_h(cap: null, floor: -0.15, strike: 100, currentLevel: 100).position,
        'X-15%-01Jan30');
  });

  test('canonicalIssuer maps known short names', () {
    expect(canonicalIssuer('Aspida'), 'ASPIDA');
    expect(canonicalIssuer('Nat. Bank of Canada'), 'NATBANK');
    expect(canonicalIssuer('NBC'), 'NATBANK');
    expect(canonicalIssuer('Unknown'), 'UNKNOWN'); // fallback: upper
  });

  test('dedupedPosition uses -IRA/-ROTH on collision; numeric fallback only when type also collides', () {
    // Same issuer/floor/maturity but different account types -> -IRA / -ROTH.
    final ira = Holding(
      issuer: 'CITI', index: '^GSPC', account: AccountType.ira,
      cap: null, participation: 1.0, floor: -0.15, floorType: FloorType.hard,
      strike: 100, currentLevel: 100,
      openDate: DateTime(2026, 1, 1), lastReset: DateTime(2026, 1, 1),
      maturity: DateTime(2030, 2, 4), nextReset: DateTime(2030, 2, 4),
      resetFreq: ResetFreq.inception, initial: 100,
    );
    final roth = Holding(
      issuer: 'CITI', index: '^GSPC', account: AccountType.roth,
      cap: null, participation: 1.0, floor: -0.15, floorType: FloorType.hard,
      strike: 100, currentLevel: 100,
      openDate: DateTime(2026, 1, 1), lastReset: DateTime(2026, 1, 1),
      maturity: DateTime(2030, 2, 4), nextReset: DateTime(2030, 2, 4),
      resetFreq: ResetFreq.inception, initial: 100,
    );
    expect(ira.position, roth.position); // same base
    final all = [ira, roth];
    expect(dedupedPosition(ira, all), '${ira.position}-IRA');
    expect(dedupedPosition(roth, all), '${roth.position}-ROTH');
    expect(dedupedPosition(ira, [ira]), ira.position); // unique → unchanged

    // Two with the SAME type still in the same base group -> numeric fallback
    // appended after -Type to disambiguate.
    final h1 = _h(cap: 0.10, floor: 0, strike: 100, currentLevel: 110);
    final h2 = _h(cap: 0.12, floor: 0, strike: 200, currentLevel: 220);
    final dup = [h1, h2];
    expect(dedupedPosition(h1, dup), '${h1.position}-Non-Qual-1');
    expect(dedupedPosition(h2, dup), '${h2.position}-Non-Qual-2');
  });

  test('days to maturity/reset', () {
    final h = _h(cap: null, floor: 0, strike: 100, currentLevel: 100);
    expect(h.daysToMaturity(DateTime(2029, 1, 1)), 365);
    expect(h.daysToReset(DateTime(2026, 12, 31)), 1);
  });
}
