// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: Apache-2.0
// Published index prices (data/market.json), refreshed by the daily 5 PM
// trading-day GitHub Action. The UI shows these as a header banner.

import 'dart:convert';

import 'package:http/http.dart' as http;

class Market {
  const Market({
    required this.asOf,
    required this.spx,
    required this.ndx,
    required this.rut,
    this.tradingDay = true,
  });

  final DateTime asOf;
  final double spx;
  final double ndx;
  final double rut;
  final bool tradingDay;

  /// Price for a holding's [Holding.baseIndex] symbol.
  double priceFor(String symbol) => switch (symbol.toUpperCase()) {
        'NDX' => ndx,
        'RUT' => rut,
        _ => spx,
      };

  Map<String, double> get bySymbol => {'SPX': spx, 'NDX': ndx, 'RUT': rut};

  factory Market.fromJson(Map<String, dynamic> j) => Market(
        asOf: DateTime.parse(j['asOf'] as String),
        spx: (j['spx'] as num).toDouble(),
        ndx: (j['ndx'] as num).toDouble(),
        rut: (j['rut'] as num).toDouble(),
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
