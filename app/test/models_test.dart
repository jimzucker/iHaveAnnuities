//
//  models_test.dart
//  iHaveAnnuities
//
//  Copyright 2026 Jim Zucker
//  SPDX-License-Identifier: Apache-2.0
//
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

  test('Income note: coupon projection + realized', () {
    final h = _h(
        cap: 0.1325,
        floor: -0.30,
        floorType: FloorType.soft,
        strike: 6583,
        currentLevel: 7140,
        realized: 1.10,
        isIncomeNote: true,
        couponProj: 0.0112);
    expect(h.projGain, closeTo(0.0112, 1e-12));
    expect(h.projValueK, closeTo(102.22, 1e-9));
  });

  test('Axa 100%: -15% within -20% buffer -> 0% -> \$100k', () {
    final h = _h(cap: 1.0, floor: -0.20, strike: 100, currentLevel: 85);
    expect(h.projGain, 0.0);
    expect(h.projValueK, closeTo(100.0, 1e-9));
  });

  test('protectionType: Absolute / Hard / Soft', () {
    expect(_h(cap: null, floor: 0, strike: 100, currentLevel: 100).protectionType,
        'Absolute');
    expect(_h(cap: null, floor: -0.10, strike: 100, currentLevel: 100).protectionType,
        'Hard');
    expect(
        _h(cap: null, floor: -0.30, floorType: FloorType.soft, strike: 100, currentLevel: 100)
            .protectionType,
        'Soft');
  });

  test('computed position = issuer-floor-maturity', () {
    expect(_h(cap: 0.1225, floor: 0, strike: 100, currentLevel: 118).position,
        'x-0%-01Jan30');
    expect(_h(cap: null, floor: -0.15, strike: 100, currentLevel: 100).position,
        'x-15%-01Jan30');
  });

  test('dedupedPosition adds -1/-2 on collisions', () {
    final h1 = _h(cap: 0.10, floor: 0, strike: 100, currentLevel: 110);
    final h2 = _h(cap: 0.12, floor: 0, strike: 200, currentLevel: 220);
    expect(h1.position, h2.position); // same issuer/floor/maturity
    final all = [h1, h2];
    expect(dedupedPosition(h1, all), '${h1.position}-1');
    expect(dedupedPosition(h2, all), '${h2.position}-2');
    expect(dedupedPosition(h1, [h1]), h1.position); // unique → unchanged
  });

  test('days to maturity/reset', () {
    final h = _h(cap: null, floor: 0, strike: 100, currentLevel: 100);
    expect(h.daysToMaturity(DateTime(2029, 1, 1)), 365);
    expect(h.daysToReset(DateTime(2026, 12, 31)), 1);
  });
}
