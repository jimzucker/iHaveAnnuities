// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: Apache-2.0
// Full-branch coverage of the payoff engine. Mirrors docs/gen_overview.py.

import 'package:flutter_test/flutter_test.dart';
import 'package:ihaveannuities/core/payoff.dart';

void main() {
  group('creditedGain', () {
    test('capped gain binds at the cap', () {
      expect(creditedGain(0.18, cap: 0.1225), closeTo(0.1225, 1e-12));
    });
    test('uncapped passes the full participated move', () {
      expect(creditedGain(0.30, cap: null), closeTo(0.30, 1e-12));
    });
    test('participation > 100% amplifies', () {
      expect(creditedGain(0.30, cap: null, participation: 1.02),
          closeTo(0.306, 1e-12));
    });
    test('participation < 100% dampens', () {
      expect(creditedGain(0.40, cap: null, participation: 0.9225),
          closeTo(0.369, 1e-12));
    });
    test('cap applies after participation', () {
      expect(creditedGain(0.20, cap: 0.115, participation: 1.0),
          closeTo(0.115, 1e-12));
    });
  });

  group('payoffReturn — upside', () {
    test('exactly at the cap', () {
      expect(payoffReturn(0.1225,
              cap: 0.1225, floor: 0, floorType: FloorType.hard),
          closeTo(0.1225, 1e-12));
    });
    test('below the cap passes through', () {
      expect(payoffReturn(0.06, cap: 0.10, floor: 0, floorType: FloorType.hard),
          closeTo(0.06, 1e-12));
    });
  });

  group('payoffReturn — 0% floor', () {
    test('positive move credited', () {
      expect(
          payoffReturn(0.18,
              cap: 0.1225, floor: 0, floorType: FloorType.hard),
          closeTo(0.1225, 1e-12));
    });
    test('negative move floored at 0', () {
      expect(payoffReturn(-0.05, cap: 0.10, floor: 0, floorType: FloorType.hard),
          0.0);
    });
  });

  group('payoffReturn — hard buffer', () {
    test('within buffer => no loss (-15% move, -20% buffer)', () {
      expect(
          payoffReturn(-0.15,
              cap: null, floor: -0.20, floorType: FloorType.hard),
          0.0);
    });
    test('partial loss beyond buffer (-22% move, -15% buffer)', () {
      expect(
          payoffReturn(-0.22,
              cap: 0.65, floor: -0.15, floorType: FloorType.hard),
          closeTo(-0.07, 1e-12));
    });
    test('exactly at buffer edge => no loss', () {
      expect(
          payoffReturn(-0.15,
              cap: null, floor: -0.15, floorType: FloorType.hard),
          0.0);
    });
    test('deeper loss (-28% move, -20% buffer)', () {
      expect(
          payoffReturn(-0.28,
              cap: 1.0, floor: -0.20, floorType: FloorType.hard),
          closeTo(-0.08, 1e-12));
    });
  });

  group('payoffReturn — soft barrier', () {
    test('held within barrier => no loss (-20% move, -30% barrier)', () {
      expect(
          payoffReturn(-0.20,
              cap: null, floor: -0.30, floorType: FloorType.soft),
          0.0);
    });
    test('exactly at barrier => held (no loss)', () {
      expect(
          payoffReturn(-0.30,
              cap: null, floor: -0.30, floorType: FloorType.soft),
          0.0);
    });
    test('breached => full 1:1 loss (-35% move, -30% barrier)', () {
      expect(
          payoffReturn(-0.35,
              cap: null, floor: -0.30, floorType: FloorType.soft),
          closeTo(-0.35, 1e-12));
    });
  });

  group('indexReturn', () {
    test('normal', () {
      expect(indexReturn(7400, 6271.19), closeTo(0.18, 1e-3));
    });
    test('throws on zero strike', () {
      expect(() => indexReturn(7400, 0), throwsArgumentError);
    });
    test('throws on negative strike', () {
      expect(() => indexReturn(7400, -1), throwsArgumentError);
    });
  });

  group('projValue', () {
    test('applies payoff to principal', () {
      expect(projValue(100, 0.1225), closeTo(112.25, 1e-12));
    });
    test('reinvests realized into the base (tracker formula)', () {
      // (100 + 1.10) * (1 + 0.0112) = 102.2323
      expect(projValue(100, 0.0112, realized: 1.10), closeTo(102.2323, 1e-3));
    });
    test('loss reduces value', () {
      expect(projValue(100, -0.35), closeTo(65.0, 1e-12));
    });
  });
}
