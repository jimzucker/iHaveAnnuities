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
import '../core/reset_event.dart';
import '../core/reset_rollover.dart';
import 'index_history.dart';
import 'market.dart';
import 'tracker_xlsx.dart';

class PortfolioStore extends ChangeNotifier {
  PortfolioStore({this.base = '', this.client});

  static const _key = 'portfolio.v1';
  static const _sortKey = 'sortColumn.v1';
  static const _ascKey = 'sortAsc.v1';
  static const _fullColKey = 'fullColumns.v1';
  static const _hideSummaryKey = 'hideSummary.v1';
  static const _hiddenIdxKey = 'hiddenIndexes.v1';
  static const _resetHistKey = 'resetHistory.v1';

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
  Set<String> _hiddenIndexes = {};
  List<ResetEvent> _resetHistory = [];

  int get sortColumn => _sortColumn;
  bool get sortAscending => _sortAscending;

  /// Whether the table shows every column (true) or a compact core view.
  bool get fullColumns => _fullColumns;

  /// Whether the prices banner + hero are hidden to maximize the list (phones).
  bool get hideSummary => _hideSummary;

  /// Index symbols the user has hidden on the combined chart (remembered).
  Set<String> get hiddenIndexes => _hiddenIndexes;

  /// Logged reset events (auto-roll audit trail), newest first.
  List<ResetEvent> get resetHistory => _resetHistory;

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

  /// Toggle an index's visibility on the combined chart; persisted.
  Future<void> toggleIndex(String symbol) async {
    _hiddenIndexes = {..._hiddenIndexes};
    _hiddenIndexes.contains(symbol)
        ? _hiddenIndexes.remove(symbol)
        : _hiddenIndexes.add(symbol);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_hiddenIdxKey, _hiddenIndexes.toList());
    notifyListeners();
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _sortColumn = prefs.getInt(_sortKey) ?? defaultSortColumn;
    _sortAscending = prefs.getBool(_ascKey) ?? true;
    _fullColumns = prefs.getBool(_fullColKey) ?? true;
    _hideSummary = prefs.getBool(_hideSummaryKey) ?? false;
    _hiddenIndexes = (prefs.getStringList(_hiddenIdxKey) ?? const []).toSet();
    final histRaw = prefs.getString(_resetHistKey);
    if (histRaw != null) {
      try {
        _resetHistory = (jsonDecode(histRaw) as List)
            .map((e) => ResetEvent.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {/* ignore corrupt cache */}
    }
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
    // Apply any resets that fell due since the data was last current.
    await _catchUpResets();
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
    await _catchUpResets(); // a new trading day may have crossed a reset date
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

  Future<void> _persistResetHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _resetHistKey, jsonEncode(_resetHistory.map((e) => e.toJson()).toList()));
  }

  /// Roll every holding forward through any reset dates that have passed (income
  /// coupons accrue; point-to-point notes lock in the period payoff at the
  /// reset-date index level and reset their strike). Idempotent — once rolled,
  /// the next reset is in the future. Runs on load and after an import, so both
  /// a kept-open portfolio and a freshly loaded `.xlsx` catch up to today.
  Future<void> _catchUpResets() async {
    if (_holdings.isEmpty) return;
    final asOf = _market?.asOf ?? DateTime.now();
    if (!_holdings.any((h) => resetDue(h, asOf))) return;

    // Both annual point-to-point notes and worst-of monthly coupons need the
    // historical index levels at each reset date.
    IndexHistory? hist;
    try {
      hist = await IndexHistory.fetch(base: base, client: client);
    } catch (_) {/* offline → leave resets pending until history loads */}
    if (hist == null) return;
    double? levelAt(String sym, DateTime date) => hist!.levelOn(sym, date);

    final seen = _resetHistory.map((e) => e.dedupeKey).toSet();
    final updated = <Holding>[];
    final added = <ResetEvent>[];
    var changed = false;
    for (final h in _holdings) {
      final r = catchUp(h, asOf, levelAt);
      if (r.events.isNotEmpty) changed = true;
      updated.add(r.holding);
      for (final e in r.events) {
        if (seen.add(e.dedupeKey)) added.add(e);
      }
    }
    if (!changed) return;
    _holdings = updated;
    _resetHistory = [...added, ..._resetHistory]
      ..sort((a, b) => b.date.compareTo(a.date));
    _revalue();
    await _persist();
    await _persistResetHistory();
    notifyListeners();
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

  /// Recompute one holding from its open date: reset to the inception state
  /// (realized 0; point-to-point strike = the index level on the open date) and
  /// replay every reset through today. Rebuilds that holding's reset-history
  /// entries. Use to repair a contract whose realized/strike has drifted.
  /// Returns the number of resets replayed, or -1 if history is unavailable.
  Future<int> recalcFromStart(Holding h) async {
    final asOf = _market?.asOf ?? DateTime.now();
    IndexHistory? hist;
    try {
      hist = await IndexHistory.fetch(base: base, client: client);
    } catch (_) {/* handled below */}
    if (hist == null) {
      _status = 'History unavailable; cannot recompute.';
      notifyListeners();
      return -1;
    }
    double? levelAt(String sym, DateTime date) => hist!.levelOn(sym, date);

    // Seed the inception state. Income-note strikes are fixed at inception, so
    // they're kept; a point-to-point strike is re-derived from the open-date
    // level (its stored strike has drifted forward through past resets).
    final inceptionStrike =
        h.isIncomeNote ? h.strike : (levelAt(h.baseIndex, h.openDate) ?? h.strike);
    final firstNext = h.resetFreq == ResetFreq.inception
        ? h.nextReset
        : advanceReset(h.openDate, h.resetFreq);
    final seed = h.copyWith(
      realized: 0.0,
      strike: inceptionStrike,
      lastReset: h.openDate,
      nextReset: firstNext,
    );

    final r = catchUp(seed, asOf, levelAt);
    final i = _holdings.indexWhere((x) => x.key == h.key);
    if (i < 0) return 0;
    _holdings[i] = r.holding;
    // Replace this holding's history with the freshly replayed events.
    _resetHistory = [
      ...r.events,
      ..._resetHistory.where((e) => e.holdingKey != h.key),
    ]..sort((a, b) => b.date.compareTo(a.date));
    _revalue();
    await _persist();
    await _persistResetHistory();
    notifyListeners();
    return r.events.length;
  }

  Future<void> replaceAll(List<Holding> holdings) async {
    _holdings = List.of(holdings);
    _revalue();
    await _persist();
    notifyListeners();
    // A freshly loaded tracker may be months stale — catch it up to today.
    await _catchUpResets();
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
    _resetHistory = [];
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    await prefs.remove(_resetHistKey);
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
  void debugSeed(List<Holding> holdings, Market market,
      {List<ResetEvent> resetHistory = const []}) {
    _holdings = List.of(holdings);
    _resetHistory = List.of(resetHistory);
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
