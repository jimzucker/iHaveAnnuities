// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: Apache-2.0
// Holds the portfolio + market data and persists to browser storage
// (shared_preferences → localStorage on web). Import/export use the tracker
// .xlsx schema; revaluation marks holdings to the latest published prices.

import 'dart:async';
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
  static const _sortKey = 'sortColumn.v1';
  static const _ascKey = 'sortAsc.v1';
  static const _fullColKey = 'fullColumns.v1';
  static const _hideSummaryKey = 'hideSummary.v1';

  /// Default sort column index = "Next Reset" in PortfolioTable's v1.2 column list.
  static const defaultSortColumn = 10;

  /// Hour (local, 24h) at/after which the once-per-day post-close refresh fires.
  /// 17:00 ≈ the 5 PM ET market-data publish (assumes an ET user).
  static const refreshTriggerHour = 17;

  Timer? _autoTimer;
  DateTime? _lastAutoRefresh;

  /// Whether a once-per-day post-close auto-refresh is due: true when [now] is
  /// at/past today's [triggerHour] and we haven't refreshed since then. Pure so
  /// it can be unit-tested without timers.
  static bool autoRefreshDue(DateTime now, DateTime? last,
      {int triggerHour = refreshTriggerHour}) {
    final trigger = DateTime(now.year, now.month, now.day, triggerHour);
    if (now.isBefore(trigger)) return false;
    return last == null || last.isBefore(trigger);
  }

  final String base;

  /// Optional injected HTTP client (tests).
  final http.Client? client;

  List<Holding> _holdings = [];
  Market? _market;
  String? _status;
  bool _refreshing = false;
  int _sortColumn = defaultSortColumn;
  bool _sortAscending = true;
  bool _fullColumns = true;
  bool _hideSummary = false;

  int get sortColumn => _sortColumn;
  bool get sortAscending => _sortAscending;

  /// Whether the table shows every column (true) or a compact core view.
  bool get fullColumns => _fullColumns;

  /// Whether the prices banner + hero are hidden to maximize the list (phones).
  bool get hideSummary => _hideSummary;

  /// True while a market refresh is in flight (drives the app-bar spinner).
  bool get refreshing => _refreshing;

  List<Holding> get holdings => List.unmodifiable(_holdings);
  Market? get market => _market;
  String? get status => _status;
  bool get isEmpty => _holdings.isEmpty;

  /// Computed display name for [h], with `-1/-2/…` suffixes on collisions.
  String labelFor(Holding h) => dedupedPosition(h, _holdings);

  double get totalInitial => _holdings.fold(0.0, (s, h) => s + h.initial);
  double get totalRealized => _holdings.fold(0.0, (s, h) => s + h.realized);
  double get totalProjValue => _holdings.fold(0.0, (s, h) => s + h.projValueK);

  /// Total UNREALIZED gain (excludes realized): projValue = initial + realized + gain.
  double get totalProjGain => totalProjValue - totalInitial - totalRealized;

  /// Load persisted holdings, then fetch + apply market prices.
  Future<void> setSort(int column, bool ascending) async {
    _sortColumn = column;
    _sortAscending = ascending;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_sortKey, column);
    await prefs.setBool(_ascKey, ascending);
    notifyListeners();
  }

  Future<void> setFullColumns(bool full) async {
    _fullColumns = full;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_fullColKey, full);
    notifyListeners();
  }

  Future<void> setHideSummary(bool hide) async {
    _hideSummary = hide;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hideSummaryKey, hide);
    notifyListeners();
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _sortColumn = prefs.getInt(_sortKey) ?? defaultSortColumn;
    _sortAscending = prefs.getBool(_ascKey) ?? true;
    _fullColumns = prefs.getBool(_fullColKey) ?? true;
    _hideSummary = prefs.getBool(_hideSummaryKey) ?? false;
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
    // While the app stays open, re-pull market.json once per day shortly after
    // the publish time — so a kept-open tab appears to update on its own.
    _autoTimer ??= Timer.periodic(
        const Duration(minutes: 20), (_) => _maybeAutoRefresh());
  }

  Future<void> _maybeAutoRefresh() async {
    final now = DateTime.now();
    if (!autoRefreshDue(now, _lastAutoRefresh)) return;
    _lastAutoRefresh = now;
    await refreshMarket();
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    super.dispose();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, jsonEncode(_holdings.map((h) => h.toJson()).toList()));
  }

  Future<void> refreshMarket() async {
    _refreshing = true;
    notifyListeners();
    try {
      _market = await Market.fetch(base: base, client: client);
      _revalue();
      _status = null;
    } catch (e) {
      _status = 'Prices unavailable (${e.runtimeType}); showing last import.';
    } finally {
      _refreshing = false;
      notifyListeners();
    }
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
