// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: LicenseRef-Proprietary

import 'package:flutter_test/flutter_test.dart';
import 'package:ihaveannuities/ui/format.dart';

void main() {
  test('exportFileName is dated and lowercase', () {
    expect(exportFileName(on: DateTime(2026, 6, 9)),
        'export_ihaveannuities_20260609');
    expect(exportFileName(on: DateTime(2026, 12, 23)),
        'export_ihaveannuities_20261223');
  });

  group('number + label formatters (exact strings)', () {
    test('moneyK renders \$000 as full dollars', () {
      expect(moneyK(112.25), '\$112,250');
      expect(moneyK(0), '\$0');
      expect(moneyK(-7.7), '-\$7,700');
    });

    test('pct is two-decimal percent', () {
      expect(pct(0.1225), '12.25%');
    });

    test('pctSigned prefixes only positives', () {
      expect(pctSigned(0), '0.00%');
      expect(pctSigned(0.10), '+10.00%');
      expect(pctSigned(-0.07), '-7.00%');
    });

    test('capLabel is Uncapped for null else a percent', () {
      expect(capLabel(null), 'Uncapped');
      expect(capLabel(0.1225), '12.25%');
    });

    test('indexLabel drops a leading worst-of', () {
      expect(indexLabel('worst-of SPX/NDX/RUT'), 'SPX/NDX/RUT');
      expect(indexLabel('^GSPC'), '^GSPC');
    });

    test('level is grouped two-decimal', () {
      expect(level(7431.5), '7,431.50');
    });

    test('relDays reads today / future / past', () {
      expect(relDays(0), 'today');
      expect(relDays(5), 'in 5 days');
      expect(relDays(-3), '3 days ago');
    });
  });
}
