// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: Apache-2.0
// Pure payoff engine. No Flutter imports — fully unit-testable.
// Mirrors docs/gen_overview.py so the app, the README, and the example
// spreadsheet all agree on the math.

import 'dart:math' as math;

/// Downside protection mechanism, encoded by the tracker's `Floor` column.
///
/// * [FloorType.hard] with a **negative** floor is a *buffer*: it absorbs the
///   first `|floor|` of losses; you lose 1:1 beyond it.
/// * [FloorType.soft] with a **negative** floor is a *barrier*: fully protected
///   unless the index breaches the floor, then the full decline applies.
/// * A floor of `0` is a *true floor*: no loss in the period.
enum FloorType { hard, soft }

/// Upside credited gain for a non-negative index move:
/// `uncapped ? participation*idx : min(cap, participation*idx)`.
double creditedGain(
  double indexReturn, {
  double? cap,
  double participation = 1.0,
}) {
  final up = participation * indexReturn;
  if (cap == null) return up;
  return math.min(cap, up);
}

/// Period payoff return for an index-linked contract.
///
/// [floor] must be `<= 0`. See [FloorType] for the downside semantics.
double payoffReturn(
  double indexReturn, {
  double? cap,
  double participation = 1.0,
  required double floor,
  required FloorType floorType,
}) {
  assert(floor <= 0, 'floor must be <= 0 (it is the protection level)');
  if (indexReturn >= 0) {
    return creditedGain(indexReturn, cap: cap, participation: participation);
  }
  if (floor == 0) return 0.0; // true 0% floor
  if (floorType == FloorType.soft) {
    // barrier: protected unless breached, then full 1:1 loss
    return indexReturn >= floor ? 0.0 : indexReturn;
  }
  // hard buffer: absorb first |floor|, lose 1:1 beyond
  return math.min(0.0, indexReturn - floor);
}

/// Raw index move since [strike]. Throws if [strike] is non-positive.
double indexReturn(double currentLevel, double strike) {
  if (strike <= 0) {
    throw ArgumentError.value(strike, 'strike', 'must be > 0');
  }
  return currentLevel / strike - 1.0;
}

/// Projected value at reset: `initial * (1 + payoff) + realized`.
double projValue(double initial, double payoff, {double realized = 0.0}) =>
    initial * (1 + payoff) + realized;
