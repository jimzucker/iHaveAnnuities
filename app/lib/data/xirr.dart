// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: LicenseRef-Proprietary
// XIRR — money-weighted annualized return for dated cash flows. Solves for the
// annual rate r where the net present value of all flows is zero, via robust
// bisection (no derivative blow-ups). Pure Dart.

import 'dart:math' as math;

/// Annualized money-weighted return for [flows] (each a (date, amount): invest
/// = negative, value/return = positive). Returns null when it can't be solved
/// (fewer than two flows, or no sign change — e.g. all the same sign).
double? xirr(List<(DateTime, double)> flows) {
  if (flows.length < 2) return null;
  if (!flows.any((f) => f.$2 < 0) || !flows.any((f) => f.$2 > 0)) return null;

  final t0 = flows.map((f) => f.$1).reduce((a, b) => a.isBefore(b) ? a : b);
  double npv(double r) {
    var s = 0.0;
    for (final (date, amount) in flows) {
      final years = date.difference(t0).inDays / 365.25;
      s += amount / math.pow(1 + r, years);
    }
    return s;
  }

  // Bracket a sign change, then bisect. NPV is monotonic in r for the usual
  // (invest early, value later) shape, so this converges reliably.
  var lo = -0.9999, hi = 10.0;
  var flo = npv(lo), fhi = npv(hi);
  var tries = 0;
  while (flo * fhi > 0 && hi < 1e6 && tries < 100) {
    hi *= 2;
    fhi = npv(hi);
    tries++;
  }
  if (flo * fhi > 0) return null; // no bracket found

  for (var i = 0; i < 200; i++) {
    final mid = (lo + hi) / 2;
    final fm = npv(mid);
    if (fm.abs() < 1e-9) return mid;
    if (flo * fm < 0) {
      hi = mid;
    } else {
      lo = mid;
      flo = fm;
    }
  }
  return (lo + hi) / 2;
}
