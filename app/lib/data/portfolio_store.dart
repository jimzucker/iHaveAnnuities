// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: LicenseRef-Proprietary
// Holds the portfolio + market data and persists to browser storage
// (shared_preferences → localStorage on web). Import/export use the tracker
// .xlsx schema; revaluation marks holdings to the latest published prices.

import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart' show SecretKey;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/models.dart';
import '../core/reset_event.dart';
import '../core/reset_rollover.dart';
import 'biometric.dart';
import 'index_history.dart';
import 'app_version.dart';
import 'market.dart';
import 'tracker_xlsx.dart';
import 'vault.dart';
import 'xirr.dart';

/// Encryption status: [disabled] = plaintext (default); [locked] = encrypted,
/// awaiting a passphrase/biometric; [unlocked] = key in memory, data readable.
enum VaultState { disabled, locked, unlocked }

class PortfolioStore extends ChangeNotifier {
  PortfolioStore(
      {this.base = marketDataBase,
      this.client,
      Vault? vault,
      BiometricAuthenticator? biometric,
      this.buildSha = appBuildSha})
      : _vault = vault ?? Vault(),
        biometric = biometric ?? defaultBiometric();

  static const _key = 'portfolio.v1';
  static const _sortKey = 'sortColumn.v1';
  static const _ascKey = 'sortAsc.v1';
  static const _fullColKey = 'fullColumns.v1';
  static const _groupByKey = 'groupBy.v1';
  static const _hideSummaryKey = 'hideSummary.v1';
  static const _hiddenIdxKey = 'hiddenIndexes.v1';
  static const _resetHistKey = 'resetHistory.v1';
  static const _vaultMetaKey = 'vault.meta.v1';
  static const _vaultSessionKey = 'vault.session.v1';
  static const _stayDaysKey = 'vault.stayDays.v1';
  static const _onboardedKey = 'onboarded.v1';
  static const _nudgedKey = 'nudgedEncryption.v1';

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

  /// The git SHA this build was compiled with (drives the "new version" prompt).
  final String buildSha;
  bool _newVersionAvailable = false;
  String? _dismissedSha; // a deployed SHA the user chose "Later" on

  /// True when a newer app version has been deployed than the one running.
  bool get newVersionAvailable => _newVersionAvailable;

  /// Crypto core + biometric authenticator (injectable for tests).
  final Vault _vault;
  final BiometricAuthenticator biometric;

  VaultState _vaultState = VaultState.disabled;
  VaultMeta? _vaultMeta;
  Uint8List? _dek; // in-memory Data Encryption Key; null unless unlocked
  int _stayUnlockedDays = 30;
  bool _ready = false; // true once init() has read local storage
  bool _onboarded = false; // first-run security wizard completed/seen
  bool _nudged = false; // one-time "encrypt your data?" nudge shown

  List<Holding> _holdings = [];
  Market? _market;
  String? _status;
  bool _refreshing = false;
  int _sortColumn = defaultSortColumn;
  bool _sortAscending = true;
  bool _fullColumns = true;
  String _groupBy = ''; // '' = no grouping; else a dimension label
  bool _hideSummary = false;
  Set<String> _hiddenIndexes = {};
  List<ResetEvent> _resetHistory = [];

  int get sortColumn => _sortColumn;
  bool get sortAscending => _sortAscending;

  /// Whether the table shows every column (true) or a compact core view.
  bool get fullColumns => _fullColumns;

  /// Table grouping dimension ('' = ungrouped). One of the labels in
  /// [groupDimensions]; the table renders a header + subtotal row per group.
  String get groupBy => _groupBy;

  /// The dimensions holdings can be grouped by (label → value extractor).
  static const groupDimensions = <String>[
    'Issuer', 'Type', 'Index', 'Protection', 'Reset Freq',
  ];

  /// Expanded group values in the table's pivot view (in-memory only — a
  /// transient view state, reset when the group-by dimension changes). Tracking
  /// the EXPANDED set means groups default to collapsed (summary-first): a group
  /// not in this set is folded to its subtotal band. Keyed by display value.
  final Set<String> _expandedGroups = {};

  bool isGroupCollapsed(String value) => !_expandedGroups.contains(value);

  /// True when no group is expanded (drives the Collapse-all/Expand-all state).
  bool get allGroupsCollapsed => _expandedGroups.isEmpty;

  void toggleGroupCollapsed(String value) {
    _expandedGroups.contains(value)
        ? _expandedGroups.remove(value)
        : _expandedGroups.add(value);
    notifyListeners();
  }

  void collapseAllGroups() {
    if (_expandedGroups.isEmpty) return;
    _expandedGroups.clear();
    notifyListeners();
  }

  void expandAllGroups(Iterable<String> values) {
    _expandedGroups.addAll(values);
    notifyListeners();
  }

  /// Whether the prices banner + hero are hidden to maximize the list (phones).
  bool get hideSummary => _hideSummary;

  /// Index symbols the user has hidden on the combined chart (remembered).
  Set<String> get hiddenIndexes => _hiddenIndexes;

  /// Logged reset events (auto-roll audit trail), newest first.
  List<ResetEvent> get resetHistory => _resetHistory;

  /// True while a market refresh is in flight (drives the app-bar spinner).
  bool get refreshing => _refreshing;

  /// Encryption status (drives the unlock gate).
  VaultState get vaultState => _vaultState;
  bool get encryptionEnabled => _vaultMeta != null;
  bool get isLocked => _vaultState == VaultState.locked;
  bool get biometricEnabled => _vaultMeta?.biometric != null;
  int get stayUnlockedDays => _stayUnlockedDays;

  /// True once init() has read local storage (gates a brief splash so the
  /// onboarding wizard doesn't flash for returning users).
  bool get ready => _ready;

  /// Show the first-run security wizard (brand-new, empty install only).
  bool get needsOnboarding => !_onboarded;

  /// One-time prompt to consider encryption after the user adds data on the
  /// skip path (only when they've onboarded, have data, and aren't encrypted).
  bool get shouldNudgeEncryption =>
      _onboarded && !encryptionEnabled && _holdings.isNotEmpty && !_nudged;

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

  /// Money-weighted annualized return (XIRR) for the whole book: each holding's
  /// principal is an outflow at its open date, today's total value the inflow.
  /// Correctly handles contracts opened on different dates. Null when it can't
  /// be solved (no holdings / no market date / degenerate flows).
  double? get portfolioXirr => xirrFor(_holdings);

  /// Money-weighted annualized return (XIRR) for an arbitrary subset — a table
  /// group or the whole book. Each holding's principal is an outflow at its
  /// return-start date, the subset's projected value the inflow at [asOf]. Same
  /// convention as [portfolioXirr]; null when unsolvable (no market date, empty,
  /// or degenerate flows).
  double? xirrFor(Iterable<Holding> items) {
    final asOf = _market?.asOf;
    final list = items.toList();
    if (asOf == null || list.isEmpty) return null;
    final projValue = list.fold(0.0, (s, h) => s + h.projValueK);
    final flows = <(DateTime, double)>[
      for (final h in list) (h.returnStart, -h.initial),
      (asOf, projValue),
    ];
    return xirr(flows);
  }

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

  /// Set the table grouping dimension ('' clears it); persisted. Changing the
  /// dimension resets the transient view state — every group starts collapsed
  /// (summary-first), so the expanded set is emptied.
  Future<void> setGroupBy(String dim) async {
    _groupBy = groupDimensions.contains(dim) ? dim : '';
    _expandedGroups.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_groupByKey, _groupBy);
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
    _groupBy = prefs.getString(_groupByKey) ?? '';
    if (!groupDimensions.contains(_groupBy)) _groupBy = '';
    _hideSummary = prefs.getBool(_hideSummaryKey) ?? false;
    _hiddenIndexes = (prefs.getStringList(_hiddenIdxKey) ?? const []).toSet();
    _stayUnlockedDays = prefs.getInt(_stayDaysKey) ?? 30;
    _onboarded = prefs.getBool(_onboardedKey) ?? false;
    _nudged = prefs.getBool(_nudgedKey) ?? false;

    final metaRaw = prefs.getString(_vaultMetaKey);
    if (metaRaw != null) {
      try {
        _vaultMeta = VaultMeta.fromJson(jsonDecode(metaRaw) as Map<String, dynamic>);
      } catch (_) {/* ignore corrupt meta */}
    }
    if (_vaultMeta != null) {
      // Encrypted: stay locked unless a still-valid "stay unlocked" session
      // restores the key (which also loads + decrypts the data).
      _vaultState = VaultState.locked;
      await _tryRestoreSession(prefs);
    } else {
      _vaultState = VaultState.disabled;
      await _loadData(prefs); // plaintext
    }
    // Returning users (existing data or a vault) skip the first-run wizard.
    if (!_onboarded && (_holdings.isNotEmpty || encryptionEnabled)) {
      _onboarded = true;
      await prefs.setBool(_onboardedKey, true);
    }
    _ready = true;
    notifyListeners();
    await refreshMarket();
    // Apply any resets that fell due since the data was last current (only when
    // we can actually read the holdings).
    if (_vaultState != VaultState.locked) await _catchUpResets();
    // While the app stays open: re-pull market.json once per day after the
    // publish time (silent auto-refresh) and check whether a newer app version
    // has been deployed (prompts the user to reload).
    await checkAppVersion();
    _autoTimer ??= Timer.periodic(const Duration(minutes: 20), (_) {
      _maybeAutoRefresh();
      checkAppVersion();
    });
  }

  String? _pendingVersionSha; // the deployed SHA currently being prompted

  /// Poll the deployed build id; flag a new version when it differs from this
  /// build's SHA (and wasn't already dismissed). No-op for local/test builds.
  Future<void> checkAppVersion() async {
    if (buildSha == 'dev' || _newVersionAvailable) return;
    final deployed = await fetchDeployedSha(client: client);
    if (deployed != null && deployed != buildSha && deployed != _dismissedSha) {
      _newVersionAvailable = true;
      _pendingVersionSha = deployed;
      notifyListeners();
    }
  }

  /// Dismiss the prompt for the current build ("Later") — won't re-nag until an
  /// even newer version is deployed.
  void dismissNewVersion() {
    _dismissedSha = _pendingVersionSha;
    _newVersionAvailable = false;
    notifyListeners();
  }

  /// Read holdings + reset-history from prefs, decrypting with the in-memory DEK
  /// when the vault is unlocked. Safe to call repeatedly.
  Future<void> _loadData(SharedPreferences prefs) async {
    var histJson = prefs.getString(_resetHistKey);
    var dataJson = prefs.getString(_key);
    if (_dek != null) {
      try {
        if (histJson != null) histJson = await _vault.decryptString(histJson, _dek!);
        if (dataJson != null) dataJson = await _vault.decryptString(dataJson, _dek!);
      } catch (_) {
        return; // can't decrypt — leave data empty
      }
    }
    if (histJson != null) {
      try {
        _resetHistory = (jsonDecode(histJson) as List)
            .map((e) => ResetEvent.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {/* ignore corrupt cache */}
    }
    if (dataJson != null) {
      try {
        _holdings = (jsonDecode(dataJson) as List)
            .map((e) => Holding.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {/* ignore corrupt cache */}
    }
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
    final json = jsonEncode(_holdings.map((h) => h.toJson()).toList());
    await prefs.setString(
        _key, _dek != null ? await _vault.encryptString(json, _dek!) : json);
  }

  // ---- Vault: session + meta persistence -----------------------------------

  Future<void> _saveMeta() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_vaultMetaKey, jsonEncode(_vaultMeta!.toJson()));
  }

  /// Persist the "stay unlocked" session (DEK + expiry). Accepted trade-off:
  /// the key sits in storage for the window so the app re-opens without a prompt.
  Future<void> _startSession() async {
    if (_dek == null) return;
    final prefs = await SharedPreferences.getInstance();
    final expires = DateTime.now().add(Duration(days: _stayUnlockedDays));
    await prefs.setString(
        _vaultSessionKey,
        jsonEncode({'dek': base64Encode(_dek!), 'expiresAt': expires.toIso8601String()}));
  }

  /// Restore an unexpired session → sets the DEK, flips to unlocked, loads data.
  Future<bool> _tryRestoreSession(SharedPreferences prefs) async {
    final raw = prefs.getString(_vaultSessionKey);
    if (raw == null) return false;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final expires = DateTime.parse(j['expiresAt'] as String);
      if (!expires.isAfter(DateTime.now())) {
        await prefs.remove(_vaultSessionKey);
        return false;
      }
      _dek = base64Decode(j['dek'] as String);
      _vaultState = VaultState.unlocked;
      await _loadData(prefs);
      return true;
    } catch (_) {
      await prefs.remove(_vaultSessionKey);
      return false;
    }
  }

  Future<void> _clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_vaultSessionKey);
  }

  Future<void> _afterUnlock() async {
    _vaultState = VaultState.unlocked;
    final prefs = await SharedPreferences.getInstance();
    await _loadData(prefs);
    await _startSession();
    _revalue();
    notifyListeners();
    await _catchUpResets();
  }

  /// Clear the reset-history log (audit trail only — holdings keep their
  /// realized; the log can be rebuilt with Recompute-from-start).
  Future<void> clearResetHistory() async {
    _resetHistory = [];
    await _persistResetHistory();
    notifyListeners();
  }

  Future<void> _persistResetHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(_resetHistory.map((e) => e.toJson()).toList());
    await prefs.setString(
        _resetHistKey, _dek != null ? await _vault.encryptString(json, _dek!) : json);
  }

  // ---- Vault: enable / unlock / recover / manage ---------------------------

  /// Turn on encryption: generate a DEK, wrap it by the passphrase and a fresh
  /// recovery code, and re-write the existing data encrypted in place. Returns
  /// the recovery code to show the user once.
  Future<String> enableEncryption(String passphrase) async {
    final dek = _vault.newDek();
    final saltPp = _vault.newSalt(), saltRc = _vault.newSalt();
    final code = _vault.newRecoveryCode();
    _vaultMeta = VaultMeta(
      kdfIterations: _vault.kdfIterations,
      saltPp: base64Encode(saltPp),
      wrapPp: await _vault.wrap(dek, await _vault.deriveKek(passphrase, saltPp)),
      saltRc: base64Encode(saltRc),
      wrapRc: await _vault.wrap(
          dek, await _vault.deriveKek(Vault.normalizeRecoveryCode(code), saltRc)),
    );
    _dek = dek;
    _vaultState = VaultState.unlocked;
    await _persist(); // re-writes the data as ciphertext
    await _persistResetHistory();
    await _saveMeta();
    await _startSession();
    notifyListeners();
    return code;
  }

  /// Unlock with the passphrase. Returns false on a wrong passphrase.
  Future<bool> unlock(String passphrase) async {
    final meta = _vaultMeta;
    if (meta == null) return false;
    try {
      final kek = await _vault.deriveKek(passphrase, base64Decode(meta.saltPp),
          iterations: meta.kdfIterations);
      _dek = await _vault.unwrap(meta.wrapPp, kek);
    } catch (_) {
      _dek = null;
      return false;
    }
    await _afterUnlock();
    return true;
  }

  /// Verify a passphrase WITHOUT changing state — used to gate destructive
  /// actions when encryption is on. Returns true when encryption is off (no
  /// passphrase to check) or the passphrase is correct.
  Future<bool> verifyPassphrase(String passphrase) async {
    final meta = _vaultMeta;
    if (meta == null) return true;
    try {
      final kek = await _vault.deriveKek(passphrase, base64Decode(meta.saltPp),
          iterations: meta.kdfIterations);
      await _vault.unwrap(meta.wrapPp, kek);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Verify the recovery code WITHOUT changing state — the "forgot passphrase"
  /// fallback for re-authentication gates.
  Future<bool> verifyRecoveryCode(String code) async {
    final meta = _vaultMeta;
    if (meta == null) return true;
    try {
      final kek = await _vault.deriveKek(
          Vault.normalizeRecoveryCode(code), base64Decode(meta.saltRc),
          iterations: meta.kdfIterations);
      await _vault.unwrap(meta.wrapRc, kek);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Verify identity via Touch ID WITHOUT changing state — the biometric
  /// equivalent of [verifyPassphrase] for gating destructive actions/Security.
  Future<bool> verifyBiometric() async {
    final bio = _vaultMeta?.biometric;
    if (bio == null) return false;
    final secret = await biometric.authenticate(bio.credentialId);
    if (secret == null) return false;
    try {
      await _vault.unwrap(bio.wrap, SecretKey(secret));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Unlock via the platform biometric (Touch ID). Returns false if cancelled.
  Future<bool> biometricUnlock() async {
    final bio = _vaultMeta?.biometric;
    if (bio == null) return false;
    final secret = await biometric.authenticate(bio.credentialId);
    if (secret == null) return false;
    try {
      _dek = await _vault.unwrap(bio.wrap, SecretKey(secret));
    } catch (_) {
      _dek = null;
      return false;
    }
    await _afterUnlock();
    return true;
  }

  /// Unlock with the recovery code (when the passphrase is forgotten). The
  /// caller should immediately set a new passphrase via [changePassphrase].
  Future<bool> recoverWithCode(String code) async {
    final meta = _vaultMeta;
    if (meta == null) return false;
    try {
      final kek = await _vault.deriveKek(
          Vault.normalizeRecoveryCode(code), base64Decode(meta.saltRc),
          iterations: meta.kdfIterations);
      _dek = await _vault.unwrap(meta.wrapRc, kek);
    } catch (_) {
      _dek = null;
      return false;
    }
    await _afterUnlock();
    return true;
  }

  /// Re-wrap the DEK under a new passphrase (must be unlocked).
  Future<void> changePassphrase(String newPassphrase) async {
    final meta = _vaultMeta, dek = _dek;
    if (meta == null || dek == null) return;
    final salt = _vault.newSalt();
    _vaultMeta = meta.copyWith(
      saltPp: base64Encode(salt),
      wrapPp: await _vault.wrap(dek, await _vault.deriveKek(newPassphrase, salt)),
    );
    await _saveMeta();
    notifyListeners();
  }

  /// Generate a fresh recovery code, re-wrapping the DEK (must be unlocked).
  Future<String?> regenerateRecoveryCode() async {
    final meta = _vaultMeta, dek = _dek;
    if (meta == null || dek == null) return null;
    final code = _vault.newRecoveryCode();
    final salt = _vault.newSalt();
    _vaultMeta = meta.copyWith(
      saltRc: base64Encode(salt),
      wrapRc: await _vault.wrap(
          dek, await _vault.deriveKek(Vault.normalizeRecoveryCode(code), salt)),
    );
    await _saveMeta();
    notifyListeners();
    return code;
  }

  /// Enroll the platform biometric as an additional unlock method (must be
  /// unlocked). Returns false if unsupported or cancelled.
  Future<bool> enableBiometric() async {
    final meta = _vaultMeta, dek = _dek;
    if (meta == null || dek == null) return false;
    if (!await biometric.isSupported()) return false;
    final enr = await biometric.enroll();
    if (enr == null) return false;
    // Prefer the secret returned at create (one prompt); otherwise derive it via
    // a single follow-up assertion. Either way it's the deterministic PRF key
    // that unlock will reproduce, so saving it is safe.
    final secret = enr.prfSecret ?? await biometric.authenticate(enr.credentialId);
    if (secret == null) return false;
    _vaultMeta = meta.copyWith(
      biometric: BiometricWrap(
          credentialId: enr.credentialId,
          wrap: await _vault.wrap(dek, SecretKey(secret))),
    );
    await _saveMeta();
    notifyListeners();
    return true;
  }

  Future<void> disableBiometric() async {
    final meta = _vaultMeta;
    if (meta == null) return;
    _vaultMeta = meta.copyWith(clearBiometric: true);
    await _saveMeta();
    notifyListeners();
  }

  /// Turn encryption off, writing the data back as plaintext (must be unlocked).
  Future<void> disableEncryption() async {
    if (_dek == null) return;
    _vaultMeta = null;
    _dek = null;
    _vaultState = VaultState.disabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_vaultMetaKey);
    await prefs.remove(_vaultSessionKey);
    await _persist(); // now plaintext
    await _persistResetHistory();
    notifyListeners();
  }

  /// Lock now: wipe the in-memory key + data and end the session.
  Future<void> lock() async {
    _dek = null;
    _holdings = [];
    _resetHistory = [];
    _vaultState = _vaultMeta != null ? VaultState.locked : VaultState.disabled;
    await _clearSession();
    notifyListeners();
  }

  /// Mark the first-run security wizard as completed/skipped.
  Future<void> markOnboarded() async {
    _onboarded = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardedKey, true);
    notifyListeners();
  }

  /// Dismiss the one-time "encrypt your data?" nudge (chosen Set up or Not now).
  Future<void> dismissEncryptionNudge() async {
    _nudged = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_nudgedKey, true);
    notifyListeners();
  }

  /// Days a device stays unlocked before re-prompting. Refreshes the live
  /// session's expiry when changed while unlocked.
  Future<void> setStayUnlockedDays(int days) async {
    _stayUnlockedDays = days;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_stayDaysKey, days);
    if (_dek != null) await _startSession();
    notifyListeners();
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
    _vaultMeta = null;
    _dek = null;
    _vaultState = VaultState.disabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    await prefs.remove(_resetHistKey);
    await prefs.remove(_vaultMetaKey);
    await prefs.remove(_vaultSessionKey);
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
    _onboarded = true; // tests pump screens directly, past the wizard
    _ready = true;
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
