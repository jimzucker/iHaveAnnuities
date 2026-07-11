// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: LicenseRef-Proprietary
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
/// * [FloorType.floor] with a **negative** floor is a *max-loss floor*: the loss
///   is limited to the floor (`max(indexReturn, floor)`) and never worse.
/// * [FloorType.none] is *no protection*: the full index decline applies 1:1
///   (the floor value is ignored).
/// * A floor of `0` is a *true floor*: no loss in the period (except [none]).
enum FloorType { hard, soft, floor, none }

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
  return switch (floorType) {
    // no protection: full 1:1 loss (floor value ignored)
    FloorType.none => indexReturn,
    // a 0% floor (any protected type) means no loss this period
    _ when floor == 0 => 0.0,
    // barrier: protected unless breached, then full 1:1 loss
    FloorType.soft => indexReturn >= floor ? 0.0 : indexReturn,
    // max-loss floor: lose down to the floor and no further
    FloorType.floor => math.max(indexReturn, floor),
    // hard buffer: absorb first |floor|, lose 1:1 beyond
    FloorType.hard => math.min(0.0, indexReturn - floor),
  };
}

/// Raw index move since [strike]. Throws if [strike] is non-positive.
double indexReturn(double currentLevel, double strike) {
  if (strike <= 0) {
    throw ArgumentError.value(strike, 'strike', 'must be > 0');
  }
  return currentLevel / strike - 1.0;
}

/// Projected value at reset, matching the Zucker tracker: realized income is
/// reinvested into the base, so the payoff applies to `(initial + realized)`:
/// `(initial + realized) * (1 + payoff)`.
double projValue(double initial, double payoff, {double realized = 0.0}) =>
    (initial + realized) * (1 + payoff);
