//
//  models.dart
//  iHaveAnnuities
//
//  Copyright 2026 Jim Zucker
//  SPDX-License-Identifier: Apache-2.0
//
// Domain model for a tracked structured-product holding. Pure Dart; mirrors the
// Zucker Annuity Tracker schema. Derived values are computed via the payoff
// engine in payoff.dart, never stored.

import 'payoff.dart';

/// Account / tax treatment.
enum AccountType { nonQual, ira, roth }

/// Reset cadence. Point-to-point terms are expressed as multi-year resets.
enum ResetFreq { annual, monthly, y4, y5, y6 }

extension ResetFreqLabel on ResetFreq {
  String get label => switch (this) {
        ResetFreq.annual => 'Annual',
        ResetFreq.monthly => 'Monthly',
        ResetFreq.y4 => '4-Year',
        ResetFreq.y5 => '5-Year',
        ResetFreq.y6 => '6-Year',
      };
}

extension AccountTypeLabel on AccountType {
  String get label => switch (this) {
        AccountType.nonQual => 'Non-Qual',
        AccountType.ira => 'IRA',
        AccountType.roth => 'ROTH',
      };
}

/// One tracked contract. Inputs map 1:1 to the tracker's blue (input) columns;
/// the getters below are the black (formula) columns.
class Holding {
  Holding({
    required this.issuer,
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
  });

  final String issuer;
  final String index; // 'SPX' | 'NDX' | 'RUT' | 'worst-of SPX/NDX/RUT'
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

  /// Index move since [strike] (fraction).
  double get indexGain => indexReturn(currentLevel, strike);

  /// Projected credited gain at the next reset (fraction).
  double get projGain => isIncomeNote
      ? couponProj
      : payoffReturn(indexGain,
          cap: cap,
          participation: participation,
          floor: floor,
          floorType: floorType);

  /// Projected value at reset, in $000.
  double get projValueK => projValue(initial, projGain, realized: realized);

  /// Projected $ gain at reset, in $000.
  double get projGainDollarsK => projValueK - initial;

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

  /// Computed display name: `Issuer-{floor/buffer %}-{maturity ddMMMyy}`,
  /// e.g. `Aspida-0%-14Nov28`, `Axa-15%-18Aug27`. Not stored or imported.
  /// Use [dedupedPosition] across a portfolio to disambiguate collisions.
  String get position =>
      '$issuer-${_trimPct(floor.abs() * 100)}%-${_ddMMMyy(maturity)}';

  /// Base index symbol used to price this holding (worst-of resolves to SPX
  /// for the simple revaluation path).
  String get baseIndex {
    final u = index.toUpperCase();
    if (u.contains('WORST')) return 'SPX'; // worst-of basket priced off SPX
    if (u.contains('NDX')) return 'NDX';
    if (u.contains('RUT')) return 'RUT';
    return 'SPX';
  }

  /// Display label for the downside protection: a 0% floor is "Absolute"
  /// (no loss); a negative floor is a "Hard" buffer or "Soft" barrier.
  String get protectionType => floor == 0
      ? 'Absolute'
      : (floorType == FloorType.soft ? 'Soft' : 'Hard');

  Holding copyWith({double? currentLevel}) => Holding(
        issuer: issuer,
        index: index,
        account: account,
        cap: cap,
        participation: participation,
        floor: floor,
        floorType: floorType,
        strike: strike,
        currentLevel: currentLevel ?? this.currentLevel,
        openDate: openDate,
        lastReset: lastReset,
        maturity: maturity,
        nextReset: nextReset,
        resetFreq: resetFreq,
        initial: initial,
        realized: realized,
        isIncomeNote: isIncomeNote,
        couponProj: couponProj,
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
      };

  factory Holding.fromJson(Map<String, dynamic> j) => Holding(
        issuer: j['issuer'] as String? ?? '',
        index: j['index'] as String? ?? 'SPX',
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
        resetFreq: ResetFreq.values.byName(j['resetFreq'] as String? ?? 'annual'),
        initial: (j['initial'] as num?)?.toDouble() ?? 100.0,
        realized: (j['realized'] as num?)?.toDouble() ?? 0.0,
        isIncomeNote: j['isIncomeNote'] as bool? ?? false,
        couponProj: (j['couponProj'] as num?)?.toDouble() ?? 0.0,
      );
}

/// Display name for [h] within [all], appending `-1`, `-2`, … when the computed
/// [Holding.position] collides with other holdings (e.g. two AIG contracts that
/// share issuer, floor, and maturity). Unique names are returned unchanged.
String dedupedPosition(Holding h, List<Holding> all) {
  final base = h.position;
  final group = all.where((x) => x.position == base).toList();
  if (group.length <= 1) return base;
  return '$base-${group.indexOf(h) + 1}';
}
