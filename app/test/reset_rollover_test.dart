// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: LicenseRef-Proprietary
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
    test('monthly from a 31st clamps to the shorter month (no overflow)', () {
      // Jan 31 + 1 month must land on Feb 28/29 — never spill into March.
      expect(advanceReset(DateTime(2026, 1, 31), ResetFreq.monthly),
          DateTime(2026, 2, 28)); // 2026 is not a leap year
      expect(advanceReset(DateTime(2028, 1, 31), ResetFreq.monthly),
          DateTime(2028, 2, 29)); // 2028 is a leap year
      // A 31st into a 30-day month clamps to the 30th.
      expect(advanceReset(DateTime(2026, 3, 31), ResetFreq.monthly),
          DateTime(2026, 4, 30));
    });
    test('monthly from December rolls into January of the next year', () {
      expect(advanceReset(DateTime(2026, 12, 16), ResetFreq.monthly),
          DateTime(2027, 1, 16));
    });
    test('annual from a leap-day clamps to Feb 28 in a common year', () {
      expect(advanceReset(DateTime(2028, 2, 29), ResetFreq.annual),
          DateTime(2029, 2, 28));
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

  test('point-to-point reset locks in a capped gain and resets the strike', () {
    final h = _h(
      cap: 0.10,
      floor: 0,
      floorType: FloorType.hard,
      strike: 100,
      initial: 100.0,
      realized: 0.0,
      lastReset: DateTime(2025, 6, 16),
      nextReset: DateTime(2026, 6, 16),
      resetFreq: ResetFreq.annual,
    );
    // level 130 → +30%, but the 10% cap binds → periodReturn clamps to 0.10.
    final r = applyReset(h, _flat(130.0));
    expect(r.event, isNotNull);
    expect(r.event!.periodReturn, closeTo(0.10, 1e-9)); // capped, not 0.30
    expect(r.event!.oldStrike, 100);
    expect(r.event!.newStrike, 130);
    expect(r.holding.strike, 130); // strike resets to the reset-date level
    expect(r.holding.realized, closeTo(100 * 0.10, 1e-9)); // base * capped return
  });

  test('income note: worst leg exactly at the barrier still earns the coupon', () {
    // Single-leg (SPX-only) income note; the barrier boundary is inclusive
    // because the engine tests `worst >= h.floor`. Uses an exactly-representable
    // barrier (-0.50 with level 50 / strike 100 → worst == -0.50 in IEEE-754)
    // so the boundary is hit precisely with no floating-point drift.
    final h = _h(
      isIncomeNote: true,
      cap: 0.12, // 1%/mo
      floor: -0.50,
      strike: 100,
      // ndxStrike / rutStrike null → SPX is the only leg.
      lastReset: DateTime(2026, 5, 16),
      nextReset: DateTime(2026, 6, 16),
    );
    // SPX 50 → worst = 50/100 - 1 = -0.50, exactly at the -50% barrier.
    double? lvl(String sym, DateTime _) => sym == 'SPX' ? 50.0 : null;
    final r = applyReset(h, lvl);
    expect(r.event!.missed, isFalse); // boundary is inclusive → coupon earned
    expect(r.event!.periodReturn, closeTo(0.01, 1e-9));
  });

  test('income note: worst leg exactly at −30% earns the coupon (float epsilon)', () {
    // 70/100 - 1 = -0.30000000000000004 in IEEE-754, a hair below -0.30. The
    // engine's 1e-9 tolerance treats a level mathematically at the barrier as
    // held, so this coupon must NOT be dropped to rounding.
    final h = _h(
      isIncomeNote: true,
      cap: 0.12, // 1%/mo
      floor: -0.30,
      strike: 100,
      lastReset: DateTime(2026, 5, 16),
      nextReset: DateTime(2026, 6, 16),
    );
    expect(70 / 100 - 1 < -0.30, isTrue); // the drift that the epsilon absorbs
    double? lvl(String sym, DateTime _) => sym == 'SPX' ? 70.0 : null;
    final r = applyReset(h, lvl);
    expect(r.event!.missed, isFalse); // barrier held despite the float wart
    expect(r.event!.periodReturn, closeTo(0.01, 1e-9));
  });

  test('income note: a missing worst-of leg bails instead of crediting a subset', () {
    // Three-leg worst-of: SPX and NDX are up, but RUT has no level yet. Deciding
    // on the two available legs would credit a coupon that a breached-but-missing
    // RUT could veto — so applyReset must return a null event and retry later.
    final h = _h(
      isIncomeNote: true,
      cap: 0.12,
      floor: -0.30,
      strike: 100,
      ndxStrike: 100,
      rutStrike: 100,
      realized: 0.5,
      lastReset: DateTime(2026, 5, 16),
      nextReset: DateTime(2026, 6, 16),
    );
    double? lvl(String sym, DateTime _) =>
        switch (sym) { 'RUT' => null, _ => 130.0 }; // RUT unknown
    final r = applyReset(h, lvl);
    expect(r.event, isNull); // incomplete data → no coupon decided
    expect(r.holding.realized, closeTo(0.5, 1e-9)); // untouched
    expect(r.holding.nextReset, DateTime(2026, 6, 16)); // schedule not advanced
    // catchUp likewise stops (retries on a later load with full data).
    final c = catchUp(h, DateTime(2026, 6, 17), lvl);
    expect(c.events, isEmpty);
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
