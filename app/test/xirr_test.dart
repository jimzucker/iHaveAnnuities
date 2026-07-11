// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: LicenseRef-Proprietary

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:ihaveannuities/data/xirr.dart';

DateTime _d(int y, [int m = 1, int day = 1]) => DateTime(y, m, day);

void main() {
  test('single 1-year investment → ~10%', () {
    final r = xirr([(_d(2026), -100.0), (_d(2027), 110.0)]);
    expect(r, isNotNull);
    expect(r!, closeTo(0.10, 2e-3));
  });

  test('two-year hold → ~10% annualized', () {
    final r = xirr([(_d(2026), -100.0), (_d(2028), 121.0)]);
    expect(r!, closeTo(0.10, 2e-3));
  });

  test('a loss yields a negative rate', () {
    final r = xirr([(_d(2026), -100.0), (_d(2027), 90.0)]);
    expect(r!, lessThan(0));
    expect(r, closeTo(-0.10, 2e-3));
  });

  test('staggered investments (mixed dates) solve to NPV≈0', () {
    final flows = [
      (_d(2025), -100.0),
      (_d(2026), -100.0),
      (_d(2027), 230.0),
    ];
    final r = xirr(flows)!;
    // Verify it's a real root: NPV at r is ~0.
    final t0 = _d(2025);
    var npv = 0.0;
    for (final (date, amt) in flows) {
      npv += amt / math.pow(1 + r, date.difference(t0).inDays / 365.25);
    }
    expect(npv, closeTo(0, 1e-3));
  });

  test('returns null without a sign change or too few flows', () {
    expect(xirr([(_d(2026), -100.0)]), isNull); // one flow
    expect(xirr([(_d(2026), -100.0), (_d(2027), -50.0)]), isNull); // all negative
    expect(xirr([(_d(2026), 100.0), (_d(2027), 50.0)]), isNull); // all positive
  });
}
