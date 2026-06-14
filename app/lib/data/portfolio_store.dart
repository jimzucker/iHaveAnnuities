//
//  portfolio_store.dart
//  iHaveAnnuities
//
//  Copyright 2026 Jim Zucker
//  SPDX-License-Identifier: Apache-2.0
//
// Holds the portfolio + market data and persists to browser storage
// (shared_preferences → localStorage on web). Import/export use the tracker
// .xlsx schema; revaluation marks holdings to the latest published prices.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/models.dart';
import 'market.dart';
import 'tracker_xlsx.dart';

class PortfolioStore extends ChangeNotifier {
  PortfolioStore({this.base = '', this.client});

  static const _key = 'portfolio.v1';
  final String base;

  /// Optional injected HTTP client (tests).
  final http.Client? client;

  List<Holding> _holdings = [];
  Market? _market;
  String? _status;

  List<Holding> get holdings => List.unmodifiable(_holdings);
  Market? get market => _market;
  String? get status => _status;
  bool get isEmpty => _holdings.isEmpty;

  double get totalInitial => _holdings.fold(0.0, (s, h) => s + h.initial);
  double get totalProjValue => _holdings.fold(0.0, (s, h) => s + h.projValueK);
  double get totalProjGain => totalProjValue - totalInitial;

  /// Load persisted holdings, then fetch + apply market prices.
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null) {
      try {
        final list = (jsonDecode(raw) as List)
            .map((e) => Holding.fromJson(e as Map<String, dynamic>))
            .toList();
        _holdings = list;
      } catch (_) {/* ignore corrupt cache */}
    }
    notifyListeners();
    await refreshMarket();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, jsonEncode(_holdings.map((h) => h.toJson()).toList()));
  }

  Future<void> refreshMarket() async {
    try {
      _market = await Market.fetch(base: base, client: client);
      _revalue();
      _status = null;
    } catch (e) {
      _status = 'Prices unavailable (${e.runtimeType}); showing last import.';
    }
    notifyListeners();
  }

  void _revalue() {
    final m = _market;
    if (m == null) return;
    _holdings = [
      for (final h in _holdings)
        h.isIncomeNote ? h : h.copyWith(currentLevel: m.priceFor(h.baseIndex)),
    ];
  }

  Future<void> replaceAll(List<Holding> holdings) async {
    _holdings = List.of(holdings);
    _revalue();
    await _persist();
    notifyListeners();
  }

  Future<void> upsert(Holding h, {Holding? replacing}) async {
    final i = replacing == null ? -1 : _holdings.indexOf(replacing);
    if (i >= 0) {
      _holdings[i] = h;
    } else {
      _holdings.add(h);
    }
    _revalue();
    await _persist();
    notifyListeners();
  }

  Future<void> remove(Holding h) async {
    _holdings.remove(h);
    await _persist();
    notifyListeners();
  }

  Future<void> clearLocal() async {
    _holdings = [];
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    notifyListeners();
  }

  /// Import from tracker `.xlsx` bytes (replaces the current portfolio).
  Future<int> importXlsx(List<int> bytes) async {
    final parsed = parseTracker(bytes);
    await replaceAll(parsed);
    return parsed.length;
  }

  /// Seed holdings + market directly (tests only; no network/persistence).
  @visibleForTesting
  void debugSeed(List<Holding> holdings, Market market) {
    _holdings = List.of(holdings);
    _market = market;
    _revalue();
    notifyListeners();
  }

  /// Export the current portfolio as tracker `.xlsx` bytes.
  List<int> exportXlsx() => writeTracker(
        _holdings,
        asOf: _market?.asOf ?? DateTime.now(),
        prices: _market?.bySymbol ?? const {'SPX': 0, 'NDX': 0, 'RUT': 0},
      );
}
