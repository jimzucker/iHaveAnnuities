// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: Apache-2.0
// Coverage for the pure reset-rollover engine.

import 'package:flutter_test/flutter_test.dart';
import 'package:ihaveannuities/core/models.dart';
import 'package:ihaveannuities/core/payoff.dart';
import 'package:ihaveannuities/core/reset_rollover.dart';

Holding _h({
  bool isIncomeNote = false,
  double? cap,
  double floor = 0.0,
  FloorType floorType = FloorType.hard,
  double strike = 100.0,
  double? ndxStrike,
  double? rutStrike,
  double initial = 10.0,
  double realized = 0.0,
  required DateTime lastReset,
  required DateTime nextReset,
  ResetFreq resetFreq = ResetFreq.monthly,
}) =>
    Holding(
      issuer: 'NATBANK',
      index: isIncomeNote ? 'SPX/NDX/RUT' : 'SPX',
      account: AccountType.nonQual,
      cap: cap,
      participation: 1.0,
      floor: floor,
      floorType: floorType,
      strike: strike,
      currentLevel: strike,
      openDate: DateTime(2026, 4, 16),
      lastReset: lastReset,
      maturity: DateTime(2029, 4, 16),
      nextReset: nextReset,
      resetFreq: resetFreq,
      initial: initial,
      realized: realized,
      isIncomeNote: isIncomeNote,
      ndxStrike: ndxStrike,
      rutStrike: rutStrike,
    );

/// A LevelAt that returns [v] for every symbol/date.
LevelAt _flat(double? v) => (_, _) => v;

void main() {
  group('advanceReset', () {
    test('monthly adds a month', () {
      expect(advanceReset(DateTime(2026, 6, 16), ResetFreq.monthly),
          DateTime(2026, 7, 16));
    });
    test('annual adds a year', () {
      expect(advanceReset(DateTime(2026, 6, 16), ResetFreq.annual),
          DateTime(2027, 6, 16));
    });
    test('inception is a no-op', () {
      expect(advanceReset(DateTime(2026, 6, 16), ResetFreq.inception),
          DateTime(2026, 6, 16));
    });
  });

  group('resetDue', () {
    final asOf = DateTime(2026, 6, 17);
    test('past reset is due', () {
      expect(
          resetDue(
              _h(lastReset: DateTime(2026, 5, 16), nextReset: DateTime(2026, 6, 16)),
              asOf),
          isTrue);
    });
    test('future reset is not due', () {
      expect(
          resetDue(
              _h(lastReset: DateTime(2026, 6, 16), nextReset: DateTime(2026, 7, 16)),
              asOf),
          isFalse);
    });
    test('a reset past maturity is not due (accrual stops at maturity)', () {
      final h = _h(
        isIncomeNote: true,
        cap: 0.12,
        lastReset: DateTime(2026, 5, 16),
        nextReset: DateTime(2026, 6, 16),
      ); // _h maturity is 2029-04-16
      // Due before maturity.
      expect(resetDue(h, DateTime(2026, 6, 17)), isTrue);
      // A note whose next reset is after its maturity never accrues again.
      final matured = _h(
        isIncomeNote: true,
        cap: 0.12,
        lastReset: DateTime(2029, 4, 16),
        nextReset: DateTime(2029, 5, 16), // past the 2029-04-16 maturity
      );
      expect(resetDue(matured, DateTime(2030, 1, 1)), isFalse);
    });

    test('catchUp stops at maturity instead of accruing forever', () {
      // Monthly note maturing 2029-04-16; far-future asOf would otherwise roll
      // dozens of coupons. It must stop at the maturity reset.
      final h = _h(
        isIncomeNote: true,
        cap: 0.12,
        lastReset: DateTime(2029, 2, 16),
        nextReset: DateTime(2029, 3, 16),
      ); // maturity 2029-04-16
      final r = catchUp(h, DateTime(2031, 1, 1), _flat(110.0));
      // Only the 16-Mar and 16-Apr (maturity) coupons; nothing past maturity.
      expect(r.events.length, 2);
      expect(r.holding.lastReset, DateTime(2029, 4, 16));
      expect(resetDue(r.holding, DateTime(2031, 1, 1)), isFalse);
    });

    test('inception never resets', () {
      expect(
          resetDue(
              _h(
                  lastReset: DateTime(2026, 5, 16),
                  nextReset: DateTime(2026, 6, 16),
                  resetFreq: ResetFreq.inception),
              asOf),
          isFalse);
    });
  });

  test('income note: worst-of coupon (cap/12) accrues on the reinvested base', () {
    // NATBANK example: cap 13.25% → 1.104%/mo, barrier −30% holds.
    final h = _h(
      isIncomeNote: true,
      cap: 0.1325,
      floor: -0.30,
      strike: 6583,
      initial: 10.0,
      realized: 0.1104,
      lastReset: DateTime(2026, 5, 16),
      nextReset: DateTime(2026, 6, 16),
    );
    // SPX 7431.46 → +12.9% worst leg, well above the −30% barrier.
    final r = applyReset(h, _flat(7431.46));
    expect(r.event!.missed, isFalse);
    // (10 + 0.1104) * (0.1325/12) = +0.1116 → realized 0.1104 → 0.2220.
    expect(r.event!.realizedAddedK, closeTo(0.1116, 1e-4));
    expect(r.holding.realized, closeTo(0.2220, 1e-4));
    expect(r.holding.nextReset, DateTime(2026, 7, 16));
    expect(r.holding.strike, 6583); // strikes never reset on income notes
  });

  test('income note: coupon missed when the worst leg breaches the barrier', () {
    final h = _h(
      isIncomeNote: true,
      cap: 0.1325,
      floor: -0.30,
      strike: 100,
      ndxStrike: 100,
      rutStrike: 100,
      realized: 0.2220,
      lastReset: DateTime(2026, 5, 16),
      nextReset: DateTime(2026, 6, 16),
    );
    // SPX/NDX hold but RUT is −40% → worst breaches the −30% barrier.
    double? lvl(String sym, DateTime _) =>
        switch (sym) { 'RUT' => 60.0, _ => 110.0 };
    final r = applyReset(h, lvl);
    expect(r.event!.missed, isTrue);
    expect(r.event!.realizedAddedK, 0.0);
    expect(r.holding.realized, closeTo(0.2220, 1e-9)); // unchanged
    expect(r.holding.nextReset, DateTime(2026, 7, 16)); // schedule still advances
  });

  test('point-to-point hard buffer locks in −7% and resets the strike', () {
    final h = _h(
      cap: 0.65,
      floor: -0.15,
      floorType: FloorType.hard,
      strike: 100,
      initial: 10.0,
      lastReset: DateTime(2025, 6, 16),
      nextReset: DateTime(2026, 6, 16),
      resetFreq: ResetFreq.annual,
    );
    // level 78 → −22% → hard buffer min(0, −0.22+0.15) = −0.07.
    final r = applyReset(h, _flat(78.0));
    expect(r.event!.periodReturn, closeTo(-0.07, 1e-9));
    expect(r.holding.realized, closeTo(10 * -0.07, 1e-9));
    expect(r.holding.strike, 78.0);
    expect(r.event!.newStrike, 78.0);
    expect(r.holding.nextReset, DateTime(2027, 6, 16));
  });

  test('point-to-point max-loss floor caps the loss at the floor', () {
    final h = _h(
      cap: 0.65,
      floor: -0.15,
      floorType: FloorType.floor,
      strike: 100,
      lastReset: DateTime(2025, 6, 16),
      nextReset: DateTime(2026, 6, 16),
      resetFreq: ResetFreq.annual,
    );
    final r = applyReset(h, _flat(78.0)); // −22% clamped to the −15% floor
    expect(r.event!.periodReturn, closeTo(-0.15, 1e-9));
  });

  test('catchUp applies multiple missed monthly coupons in order', () {
    final h = _h(
      isIncomeNote: true,
      cap: 0.12, // 1%/mo
      floor: -0.30,
      strike: 100,
      lastReset: DateTime(2026, 1, 16),
      nextReset: DateTime(2026, 2, 16),
    );
    // Level 110 every period → worst +10% holds; Feb..Jun = 5 coupons.
    final r = catchUp(h, DateTime(2026, 6, 17), _flat(110.0));
    expect(r.events.length, 5);
    expect(r.holding.nextReset, DateTime(2026, 7, 16));
    expect(resetDue(r.holding, DateTime(2026, 6, 17)), isFalse); // idempotent
    expect(r.holding.realized,
        closeTo(10 * (1.01 * 1.01 * 1.01 * 1.01 * 1.01 - 1), 1e-9));
  });

  test('catchUp stops when a level is unavailable (no guessing)', () {
    final h = _h(
      cap: null,
      floor: 0,
      strike: 100,
      lastReset: DateTime(2025, 6, 16),
      nextReset: DateTime(2026, 6, 16),
      resetFreq: ResetFreq.annual,
    );
    final r = catchUp(h, DateTime(2026, 6, 17), _flat(null));
    expect(r.events, isEmpty);
    expect(r.holding.nextReset, DateTime(2026, 6, 16)); // untouched
  });

  test('catchUp is a no-op when nothing is due', () {
    final h = _h(
      isIncomeNote: true,
      cap: 0.12,
      floor: -0.30,
      lastReset: DateTime(2026, 6, 16),
      nextReset: DateTime(2026, 7, 16),
    );
    final r = catchUp(h, DateTime(2026, 6, 17), _flat(110.0));
    expect(r.events, isEmpty);
    expect(r.holding.realized, h.realized);
  });
}
