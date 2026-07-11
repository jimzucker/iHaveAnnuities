// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: LicenseRef-Proprietary
// Pure reset-rollover logic. No Flutter / no I/O, so it's fully unit-testable.
// Mirrors the Zucker tracker's daily maintenance script:
//
//  * Monthly income notes pay a WORST-OF contingent coupon: rate = cap / 12,
//    credited only if the worst of SPX/NDX/RUT (each vs its FIXED inception
//    strike) is at or above the floor barrier; otherwise the coupon is missed.
//    Strikes never reset. Realized compounds on (initial + realized).
//  * Annual point-to-point notes lock in the period payoff (the app's
//    per-contract payoff engine — buffer / barrier / floor) at the index level
//    on the reset date, then reset the strike to that level.

import 'models.dart';
import 'payoff.dart';
import 'reset_event.dart';

/// Supplies the closing level for [symbol] on [date] (null when unknown).
typedef LevelAt = double? Function(String symbol, DateTime date);

/// The next reset date after [from] for [freq]. `inception` notes never reset
/// during the term, so they return [from] unchanged (callers guard with
/// [resetDue], which is always false for inception).
DateTime advanceReset(DateTime from, ResetFreq freq) => switch (freq) {
      ResetFreq.monthly => DateTime(from.year, from.month + 1, from.day),
      ResetFreq.annual => DateTime(from.year + 1, from.month, from.day),
      ResetFreq.inception => from,
    };

/// Whether [h] has a reset on or before [asOf] that hasn't been processed yet.
/// Accrual stops at maturity — a reset dated after the maturity date is never
/// processed (the contract has ended), so a matured note can't keep crediting.
bool resetDue(Holding h, DateTime asOf) =>
    h.resetFreq != ResetFreq.inception &&
    !h.nextReset.isAfter(asOf) &&
    !h.nextReset.isAfter(h.maturity);

/// Apply ONE reset to [h] (the one at `h.nextReset`), using [levelAt] for the
/// index level(s) on the reset date. Returns the updated holding and the logged
/// event, or a null event when the needed level isn't available (so the caller
/// can stop and retry later rather than guess).
({Holding holding, ResetEvent? event}) applyReset(Holding h, LevelAt levelAt) {
  final resetDate = h.nextReset;
  final base = h.initial + h.realized; // reinvested base

  if (h.isIncomeNote) {
    // Worst-of contingent coupon. Strikes are fixed (SPX = strike, NDX/RUT =
    // their strikes); the coupon pays iff the worst leg holds the barrier.
    final legs = <double>[];
    void leg(double? strike, String symbol) {
      if (strike == null || strike <= 0) return;
      final lvl = levelAt(symbol, resetDate);
      if (lvl != null) legs.add(lvl / strike - 1);
    }

    leg(h.strike, 'SPX');
    leg(h.ndxStrike, 'NDX');
    leg(h.rutStrike, 'RUT');
    if (legs.isEmpty) return (holding: h, event: null); // no data yet

    final worst = legs.reduce((a, b) => a < b ? a : b);
    final held = worst >= h.floor; // barrier holds → coupon earned
    final rate = (h.cap ?? 0) / 12; // monthly = annual cap / 12
    final periodReturn = held ? rate : 0.0;
    final added = base * periodReturn;
    final newRealized = h.realized + added;
    final holding = h.copyWith(
      realized: newRealized,
      lastReset: resetDate,
      nextReset: advanceReset(resetDate, h.resetFreq),
    );
    final event = ResetEvent(
      holdingKey: h.key,
      label: h.position,
      date: resetDate,
      isIncomeNote: true,
      periodReturn: periodReturn,
      realizedAddedK: added,
      realizedAfterK: newRealized,
      missed: !held,
    );
    return (holding: holding, event: event);
  }

  // Point-to-point: lock in the per-contract payoff at the reset-date level.
  final level = levelAt(h.baseIndex, resetDate);
  if (level == null) return (holding: h, event: null);
  final periodReturn = payoffReturn(
    indexReturn(level, h.strike),
    cap: h.cap,
    participation: h.participation,
    floor: h.floor,
    floorType: h.floorType,
  );
  final added = base * periodReturn;
  final newRealized = h.realized + added;
  final holding = h.copyWith(
    realized: newRealized,
    lastReset: resetDate,
    nextReset: advanceReset(resetDate, h.resetFreq),
    strike: level, // strike resets to the index level on the reset date
  );
  final event = ResetEvent(
    holdingKey: h.key,
    label: h.position,
    date: resetDate,
    isIncomeNote: false,
    periodReturn: periodReturn,
    realizedAddedK: added,
    realizedAfterK: newRealized,
    oldStrike: h.strike,
    newStrike: level,
  );
  return (holding: holding, event: event);
}

/// Roll [h] forward through every reset on or before [asOf], applying each in
/// order. Stops (leaving the holding where it is) if a needed level is missing,
/// so nothing is guessed. Returns the caught-up holding and the events applied.
({Holding holding, List<ResetEvent> events}) catchUp(
  Holding h,
  DateTime asOf,
  LevelAt levelAt,
) {
  final events = <ResetEvent>[];
  var current = h;
  // Bound the loop defensively (decades of monthly resets) against bad dates.
  for (var guard = 0; resetDue(current, asOf) && guard < 1200; guard++) {
    final r = applyReset(current, levelAt);
    final event = r.event;
    if (event == null) break; // missing level → retry on a later load
    events.add(event);
    current = r.holding;
  }
  return (holding: current, events: events);
}
