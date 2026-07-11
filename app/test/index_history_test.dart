// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: LicenseRef-Proprietary

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:ihaveannuities/data/index_history.dart';
import 'package:ihaveannuities/data/market.dart' show HttpException;

int _e(int y, int m, int d) =>
    DateTime.utc(y, m, d).millisecondsSinceEpoch ~/ 1000;

final _json = jsonEncode({
  'asOf': '2026-06-15',
  'daily': {
    'SPX': [
      [_e(2024, 1, 2), 100],
      [_e(2025, 6, 1), 120],
      [_e(2026, 1, 2), 130],
      [_e(2026, 6, 1), 140],
      [_e(2026, 6, 15), 150],
    ],
  },
  'intraday': {
    'SPX': [
      [_e(2026, 6, 13), 148],
      [_e(2026, 6, 14), 149],
      [_e(2026, 6, 15), 150],
    ],
  },
});

void main() {
  group('IndexHistory', () {
    test('parses series + range filtering (daily vs intraday)', () {
      final h = IndexHistory.parse(_json);
      expect(h.daily['SPX']!.length, 5);
      expect(h.series('SPX', HistoryRange.max).length, 5);
      expect(h.series('SPX', HistoryRange.twoY).length, 4); // drops 2024-01
      expect(h.series('SPX', HistoryRange.oneY).length, 3); // drops 2024,2025-06
      expect(h.series('SPX', HistoryRange.ytd).length, 3); // 2026 only
      expect(h.series('SPX', HistoryRange.oneM).length, 2); // last 30d
      // 1D/1W read the intraday bucket
      expect(h.series('SPX', HistoryRange.oneW).length, 3);
      expect(h.series('SPX', HistoryRange.oneD).length, 2);
      // last close is preserved as the final point
      expect(h.series('SPX', HistoryRange.max).last.$2, 150.0);
      // unknown symbol → empty
      expect(h.series('XXX', HistoryRange.max), isEmpty);
    });

    test('range labels', () {
      expect(HistoryRange.ytd.label, 'YTD');
      expect(HistoryRange.oneD.label, '1D');
      expect(HistoryRange.max.label, 'Max');
    });

    test('fetch success + non-200', () async {
      final ok = MockClient((_) async => http.Response(_json, 200));
      final h = await IndexHistory.fetch(client: ok);
      expect(h.daily['SPX']!.length, 5);

      final bad = MockClient((_) async => http.Response('nope', 404));
      expect(() => IndexHistory.fetch(client: bad), throwsA(isA<HttpException>()));
    });
  });
}
