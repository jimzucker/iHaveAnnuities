// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: Apache-2.0
// Index price history (data/history.json), refreshed by the daily Action. Used
// by the tap-through index chart. Server-side fetch avoids browser CORS.

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'market.dart' show HttpException;

/// Selectable chart ranges.
enum HistoryRange { oneD, oneW, oneM, ytd, oneY, twoY, max }

extension HistoryRangeLabel on HistoryRange {
  String get label => switch (this) {
        HistoryRange.oneD => '1D',
        HistoryRange.oneW => '1W',
        HistoryRange.oneM => '1M',
        HistoryRange.ytd => 'YTD',
        HistoryRange.oneY => '1Y',
        HistoryRange.twoY => '2Y',
        HistoryRange.max => 'Max',
      };
}

/// A single (time, close) sample.
typedef SeriesPoint = (DateTime t, double c);

class IndexHistory {
  IndexHistory({required this.asOf, required this.daily, required this.intraday});

  final DateTime asOf;
  final Map<String, List<SeriesPoint>> daily;
  final Map<String, List<SeriesPoint>> intraday;

  static List<SeriesPoint> _points(dynamic arr) => [
        for (final p in (arr as List? ?? const []))
          (
            DateTime.fromMillisecondsSinceEpoch((p[0] as num).toInt() * 1000),
            (p[1] as num).toDouble()
          ),
      ];

  factory IndexHistory.fromJson(Map<String, dynamic> j) {
    Map<String, List<SeriesPoint>> bucket(String key) {
      final src = (j[key] as Map?) ?? const {};
      return {
        for (final e in src.entries) e.key as String: _points(e.value),
      };
    }

    return IndexHistory(
      asOf: DateTime.tryParse(j['asOf'] as String? ?? '') ?? DateTime(2026),
      daily: bucket('daily'),
      intraday: bucket('intraday'),
    );
  }

  static IndexHistory parse(String body) =>
      IndexHistory.fromJson(jsonDecode(body) as Map<String, dynamic>);

  /// Points for [symbol] over [range] — intraday for 1D/1W, daily otherwise.
  List<SeriesPoint> series(String symbol, HistoryRange range) {
    final intra = range == HistoryRange.oneD || range == HistoryRange.oneW;
    final src = (intra ? intraday[symbol] : daily[symbol]) ?? const [];
    if (src.isEmpty || range == HistoryRange.max) return src;
    final last = src.last.$1;
    final from = switch (range) {
      HistoryRange.oneD => last.subtract(const Duration(days: 1)),
      HistoryRange.oneW => last.subtract(const Duration(days: 7)),
      HistoryRange.oneM => last.subtract(const Duration(days: 30)),
      HistoryRange.ytd => DateTime(last.year),
      HistoryRange.oneY => last.subtract(const Duration(days: 365)),
      HistoryRange.twoY => last.subtract(const Duration(days: 730)),
      HistoryRange.max => last,
    };
    return src.where((p) => !p.$1.isBefore(from)).toList();
  }

  /// Closing level for [symbol] on the last trading day at or before [date]
  /// (falls back to the earliest sample if [date] precedes all history).
  /// Null when there's no daily history for the symbol.
  double? levelOn(String symbol, DateTime date) {
    final pts = daily[symbol];
    if (pts == null || pts.isEmpty) return null;
    SeriesPoint? atOrBefore;
    for (final p in pts) {
      if (p.$1.isAfter(date)) break; // daily series is ascending by time
      atOrBefore = p;
    }
    return (atOrBefore ?? pts.first).$2;
  }

  static Future<IndexHistory> fetch({String base = '', http.Client? client}) async {
    final c = client ?? http.Client();
    try {
      final res = await c.get(Uri.parse('${base}history.json'));
      if (res.statusCode != 200) {
        throw HttpException('history.json ${res.statusCode}');
      }
      return parse(res.body);
    } finally {
      if (client == null) c.close();
    }
  }
}
