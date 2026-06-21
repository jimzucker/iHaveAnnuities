// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: Apache-2.0
// Domain model for a tracked structured-product holding. Pure Dart; mirrors the
// Zucker Annuity Tracker schema v1.0. Derived values are computed via the
// payoff engine in payoff.dart, never stored.

import 'payoff.dart';

/// Account / tax treatment.
enum AccountType { nonQual, ira, roth }

/// Reset cadence.
/// * [ResetFreq.inception] — point-to-point: one observation at maturity; no resets during term.
/// * [ResetFreq.annual] — resets every year.
/// * [ResetFreq.monthly] — resets every month (income-note coupon cadence).
enum ResetFreq { inception, annual, monthly }

/// Upside status of a holding's current period (drives the table highlight).
enum GainStatus { loss, flat, gain, capped }

extension ResetFreqLabel on ResetFreq {
  String get label => switch (this) {
        ResetFreq.inception => 'Inception',
        ResetFreq.annual => 'Annual',
        ResetFreq.monthly => 'Monthly',
      };
}

extension AccountTypeLabel on AccountType {
  String get label => switch (this) {
        AccountType.nonQual => 'Non-Qual',
        AccountType.ira => 'IRA',
        AccountType.roth => 'ROTH',
      };
}

/// Canonical uppercase issuer short names. Anything in the keys (case-insensitive,
/// punctuation/space tolerant) maps to the value. Unknown issuers pass through
/// upper-cased.
const Map<String, String> _issuerCanon = {
  'aspida': 'ASPIDA',
  'athene': 'ATHENE',
  'aig': 'AIG',
  'axa': 'AXA',
  'symetra': 'SYMETRA',
  'citi': 'CITI',
  'hsbc': 'HSBC',
  'bnp': 'BNP',
  'brighthouse': 'BRIGHTHOUSE',
  'natbank': 'NATBANK',
  'nationalbankofcanada': 'NATBANK',
  'natbankofcanada': 'NATBANK',
  'natbankcanada': 'NATBANK',
  'nbc': 'NATBANK',
};

String canonicalIssuer(String raw) {
  final key = raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  return _issuerCanon[key] ?? raw.toUpperCase();
}

/// One tracked contract. Inputs map 1:1 to the tracker's blue (input) columns;
/// the getters below are the black (formula) columns.
class Holding {
  Holding({
    required String issuer,
    required this.index,
    required this.account,
    required this.cap, // null == uncapped
    required this.participation,
    required this.floor, // <= 0
    required this.floorType,
    required this.strike,
    required this.currentLevel,
    required this.openDate,
    required this.lastReset,
    required this.maturity,
    required this.nextReset,
    required this.resetFreq,
    required this.initial, // principal, in $000
    this.realized = 0.0, // in $000
    this.isIncomeNote = false,
    this.couponProj = 0.0, // projected coupon for income notes (fraction)
    this.ndxStrike, // worst-of only; else null
    this.rutStrike, // worst-of only; else null
  }) : issuer = canonicalIssuer(issuer);

  final String issuer;
  final String index; // '^GSPC' | '^NDX' | '^RUT' | 'SPX/NDX/RUT' (worst-of)
  final AccountType account;
  final double? cap;
  final double participation;
  final double floor;
  final FloorType floorType;
  final double strike;
  final double currentLevel;
  final DateTime openDate;
  final DateTime lastReset;
  final DateTime maturity;
  final DateTime nextReset;
  final ResetFreq resetFreq;
  final double initial;
  final double realized;
  final bool isIncomeNote;
  final double couponProj;
  final double? ndxStrike;
  final double? rutStrike;

  /// Index move since [strike] (fraction).
  double get indexGain => indexReturn(currentLevel, strike);

  /// Monthly contingent-coupon rate for an income note = annual cap / 12
  /// (matches the reset engine). Falls back to the stored [couponProj] when no
  /// cap is present, so display and the realized roll-forward always agree.
  double get couponRate =>
      isIncomeNote && cap != null ? cap! / 12 : couponProj;

  /// Projected credited gain at the next reset (fraction).
  double get projGain => isIncomeNote
      ? couponRate
      : payoffReturn(indexGain,
          cap: cap,
          participation: participation,
          floor: floor,
          floorType: floorType);

  /// Projected value at reset, in $000.
  double get projValueK => projValue(initial, projGain, realized: realized);

  /// Unrealized $ gain at reset, in $000 — matches the tracker: the payoff on
  /// the reinvested base. By construction: projValue = initial + realized + this.
  double get projGainDollarsK => (initial + realized) * projGain;

  /// Realized return to date as a fraction of principal (income banked /
  /// initial). Always ≥ 0; 0 when there is no principal.
  double get realizedPct => initial == 0 ? 0 : realized / initial;

  /// All-in projected return: (projected value − principal) / principal =
  /// realized% + unrealized%. 0 when there is no principal.
  double get totalReturnPct => initial == 0 ? 0 : (projValueK - initial) / initial;

  /// Upside status of the current period:
  ///  - `loss`     — projected payoff is negative
  ///  - `capped`   — a positive gain that has reached the cap (ceilinged)
  ///  - `gain`     — a positive gain with room left (or uncapped)
  ///  - `flat`     — exactly zero
  GainStatus get gainStatus {
    if (projGain < 0) return GainStatus.loss;
    if (projGain == 0) return GainStatus.flat;
    final c = cap;
    if (!isIncomeNote && c != null && participation * indexGain >= c - 1e-9) {
      return GainStatus.capped;
    }
    return GainStatus.gain;
  }

  /// True when this holding carries a cap that could be reached (i.e. it makes
  /// sense to show a "cap reached / room left" indicator).
  bool get hasCap => cap != null && !isIncomeNote;

  int daysToMaturity(DateTime asOf) => maturity.difference(asOf).inDays;
  int daysToReset(DateTime asOf) => nextReset.difference(asOf).inDays;

  static const _mon = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  static String _ddMMMyy(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}${_mon[d.month - 1]}'
      '${(d.year % 100).toString().padLeft(2, '0')}';

  static String _trimPct(double v) {
    var s = v.toStringAsFixed(2);
    if (s.contains('.')) {
      s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
    }
    return s;
  }

  /// Computed display name: `{ISSUER}-{|floor|%}-{maturity ddMMMyy}`,
  /// e.g. `ASPIDA-0%-14Nov28`, `AXA-15%-18Aug27`. Output-only (never read
  /// from input). Use [dedupedPosition] across a portfolio to disambiguate
  /// collisions with `-IRA` / `-ROTH` suffix.
  String get position =>
      '$issuer-${_trimPct(floor.abs() * 100)}%-${_ddMMMyy(maturity)}';

  /// Base index symbol used to price this holding (worst-of resolves to SPX
  /// for the simple revaluation path). Accepts short names or Yahoo tickers.
  String get baseIndex {
    final u = index.toUpperCase();
    if (u.contains('/') || u.contains('WORST')) return 'SPX';
    if (u.contains('DJI') || u.contains('DOW')) return 'DJI';
    if (u.contains('IXIC') || u.contains('COMP')) return 'COMP'; // Nasdaq Composite
    if (u.contains('NDX')) return 'NDX'; // Nasdaq-100
    if (u.contains('RUT')) return 'RUT';
    return 'SPX';
  }

  /// Display label for the downside protection (v1.0 vocab):
  /// `Protected` (floor=0), `Hard` (buffer), `Soft` (barrier).
  String get protectionType => floor == 0
      ? 'Floor' // a 0% floor is just a Floor at 0% (was "Protected")
      : switch (floorType) {
          FloorType.soft => 'Soft',
          FloorType.floor => 'Floor',
          FloorType.hard => 'Hard',
        };

  /// Stable identity across re-imports (issuer/index/account/maturity don't
  /// change on a reset) — used to key reset-history entries.
  String get key => '$issuer|$index|${account.name}|${maturity.toIso8601String()}';

  Holding copyWith({
    double? currentLevel,
    double? strike,
    double? realized,
    DateTime? lastReset,
    DateTime? nextReset,
  }) =>
      Holding(
        issuer: issuer,
        index: index,
        account: account,
        cap: cap,
        participation: participation,
        floor: floor,
        floorType: floorType,
        strike: strike ?? this.strike,
        currentLevel: currentLevel ?? this.currentLevel,
        openDate: openDate,
        lastReset: lastReset ?? this.lastReset,
        maturity: maturity,
        nextReset: nextReset ?? this.nextReset,
        resetFreq: resetFreq,
        initial: initial,
        realized: realized ?? this.realized,
        isIncomeNote: isIncomeNote,
        couponProj: couponProj,
        ndxStrike: ndxStrike,
        rutStrike: rutStrike,
      );

  Map<String, dynamic> toJson() => {
        'issuer': issuer,
        'index': index,
        'account': account.name,
        'cap': cap,
        'participation': participation,
        'floor': floor,
        'floorType': floorType.name,
        'strike': strike,
        'currentLevel': currentLevel,
        'openDate': openDate.toIso8601String(),
        'lastReset': lastReset.toIso8601String(),
        'maturity': maturity.toIso8601String(),
        'nextReset': nextReset.toIso8601String(),
        'resetFreq': resetFreq.name,
        'initial': initial,
        'realized': realized,
        'isIncomeNote': isIncomeNote,
        'couponProj': couponProj,
        if (ndxStrike != null) 'ndxStrike': ndxStrike,
        if (rutStrike != null) 'rutStrike': rutStrike,
      };

  factory Holding.fromJson(Map<String, dynamic> j) => Holding(
        issuer: j['issuer'] as String? ?? '',
        index: j['index'] as String? ?? '^GSPC',
        account: AccountType.values.byName(j['account'] as String? ?? 'nonQual'),
        cap: (j['cap'] as num?)?.toDouble(),
        participation: (j['participation'] as num?)?.toDouble() ?? 1.0,
        floor: (j['floor'] as num?)?.toDouble() ?? 0.0,
        floorType: FloorType.values.byName(j['floorType'] as String? ?? 'hard'),
        strike: (j['strike'] as num?)?.toDouble() ?? 0,
        currentLevel: (j['currentLevel'] as num?)?.toDouble() ?? 0,
        openDate: DateTime.parse(j['openDate'] as String),
        lastReset: DateTime.parse(j['lastReset'] as String),
        maturity: DateTime.parse(j['maturity'] as String),
        nextReset: DateTime.parse(j['nextReset'] as String),
        resetFreq: _resetFreqFromJson(j['resetFreq'] as String?),
        initial: (j['initial'] as num?)?.toDouble() ?? 100.0,
        realized: (j['realized'] as num?)?.toDouble() ?? 0.0,
        isIncomeNote: j['isIncomeNote'] as bool? ?? false,
        couponProj: (j['couponProj'] as num?)?.toDouble() ?? 0.0,
        ndxStrike: (j['ndxStrike'] as num?)?.toDouble(),
        rutStrike: (j['rutStrike'] as num?)?.toDouble(),
      );
}

ResetFreq _resetFreqFromJson(String? s) => switch (s) {
      'inception' || 'y4' || 'y5' || 'y6' => ResetFreq.inception,
      'monthly' => ResetFreq.monthly,
      _ => ResetFreq.annual,
    };

/// Display name for [h] within [all], appending `-IRA` / `-ROTH` (the account
/// type label) when the computed [Holding.position] collides with other
/// holdings — e.g. two CITI contracts that share issuer, floor, and maturity
/// but live in different account types. Falls back to a numeric tie-breaker
/// only if the type-suffixed name also collides. Unique names returned
/// unchanged.
String dedupedPosition(Holding h, List<Holding> all) {
  final base = h.position;
  final sameBase = all.where((x) => x.position == base).toList();
  if (sameBase.length <= 1) return base;
  final byType = '$base-${h.account.label}';
  final sameByType = all
      .where((x) => '${x.position}-${x.account.label}' == byType)
      .toList();
  if (sameByType.length <= 1) return byType;
  return '$byType-${sameByType.indexOf(h) + 1}';
}
