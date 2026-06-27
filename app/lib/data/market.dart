// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: Apache-2.0
// Published index prices (market.json), refreshed by the daily 5 PM trading-day
// GitHub Action. The UI shows these as a header banner.

import 'dart:convert';

import 'package:http/http.dart' as http;

/// Base URL for the published market data. The daily Action commits `market.json`
/// and `history.json` to the orphan `market-data` branch (keeping `main`'s
/// history clean); raw.githubusercontent serves them CORS-enabled.
const marketDataBase =
    'https://raw.githubusercontent.com/jimzucker/iHaveAnnuities/market-data/';

class Market {
  const Market({
    required this.asOf,
    required this.spx,
    required this.ndx,
    required this.rut,
    this.dow,
    this.comp,
    this.tradingDay = true,
  });

  final DateTime asOf;
  final double spx;
  final double ndx;
  final double rut;

  /// Dow Jones Industrial Average (`^DJI`) and Nasdaq Composite (`^IXIC`).
  /// Nullable so an older `market.json` without these fields still loads.
  final double? dow;
  final double? comp;
  final bool tradingDay;

  /// Price for a holding's [Holding.baseIndex] symbol. Falls back to SPX when a
  /// requested index is missing from this (older) market payload.
  double priceFor(String symbol) => switch (symbol.toUpperCase()) {
        'NDX' => ndx,
        'RUT' => rut,
        'DJI' => dow ?? spx,
        'COMP' => comp ?? spx,
        _ => spx,
      };

  Map<String, double> get bySymbol => {
        'SPX': spx,
        'NDX': ndx,
        'RUT': rut,
        'DJI': ?dow,
        'COMP': ?comp,
      };

  factory Market.fromJson(Map<String, dynamic> j) => Market(
        asOf: DateTime.parse(j['asOf'] as String),
        spx: (j['spx'] as num).toDouble(),
        ndx: (j['ndx'] as num).toDouble(),
        rut: (j['rut'] as num).toDouble(),
        dow: (j['dow'] as num?)?.toDouble(),
        comp: (j['comp'] as num?)?.toDouble(),
        tradingDay: j['tradingDay'] as bool? ?? true,
      );

  static Market parse(String body) =>
      Market.fromJson(jsonDecode(body) as Map<String, dynamic>);

  /// Fetch the published market file. [base] lets the web build resolve it
  /// relative to the Pages base-href.
  static Future<Market> fetch({String base = '', http.Client? client}) async {
    final c = client ?? http.Client();
    try {
      final res = await c.get(Uri.parse('${base}market.json'));
      if (res.statusCode != 200) {
        throw HttpException('market.json ${res.statusCode}');
      }
      return parse(res.body);
    } finally {
      if (client == null) c.close();
    }
  }
}

class HttpException implements Exception {
  HttpException(this.message);
  final String message;
  @override
  String toString() => 'HttpException: $message';
}
