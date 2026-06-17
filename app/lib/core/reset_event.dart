// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: Apache-2.0
// A logged reset: what the app credited when a holding's reset date passed.
// Kept as an audit trail so the auto-roll of realized income / strikes is
// transparent and reviewable.

/// One recorded reset event for a holding.
class ResetEvent {
  ResetEvent({
    required this.holdingKey,
    required this.label,
    required this.date,
    required this.isIncomeNote,
    required this.periodReturn,
    required this.realizedAddedK,
    required this.realizedAfterK,
    this.oldStrike,
    this.newStrike,
    this.missed = false,
  });

  /// Stable [Holding.key] of the holding this reset belongs to.
  final String holdingKey;

  /// Human-readable holding label at the time of the reset (e.g. position).
  final String label;

  /// The reset date that was processed.
  final DateTime date;

  final bool isIncomeNote;

  /// Credited return for the period (fraction): the coupon for income notes,
  /// or the locked-in index payoff for point-to-point notes.
  final double periodReturn;

  /// Dollars (in $000) added to realized for this reset.
  final double realizedAddedK;

  /// Resulting realized total (in $000) after this reset.
  final double realizedAfterK;

  /// Point-to-point only: strike before/after the reset (index level on date).
  final double? oldStrike;
  final double? newStrike;

  /// Income-note only: the contingent coupon was missed (worst index breached
  /// the barrier this period), so no coupon was credited.
  final bool missed;

  Map<String, dynamic> toJson() => {
        'holdingKey': holdingKey,
        'label': label,
        'date': date.toIso8601String(),
        'isIncomeNote': isIncomeNote,
        'periodReturn': periodReturn,
        'realizedAddedK': realizedAddedK,
        'realizedAfterK': realizedAfterK,
        if (oldStrike != null) 'oldStrike': oldStrike,
        if (newStrike != null) 'newStrike': newStrike,
        if (missed) 'missed': true,
      };

  factory ResetEvent.fromJson(Map<String, dynamic> j) => ResetEvent(
        holdingKey: j['holdingKey'] as String? ?? '',
        label: j['label'] as String? ?? '',
        date: DateTime.parse(j['date'] as String),
        isIncomeNote: j['isIncomeNote'] as bool? ?? false,
        periodReturn: (j['periodReturn'] as num?)?.toDouble() ?? 0.0,
        realizedAddedK: (j['realizedAddedK'] as num?)?.toDouble() ?? 0.0,
        realizedAfterK: (j['realizedAfterK'] as num?)?.toDouble() ?? 0.0,
        oldStrike: (j['oldStrike'] as num?)?.toDouble(),
        newStrike: (j['newStrike'] as num?)?.toDouble(),
        missed: j['missed'] as bool? ?? false,
      );

  /// De-dupe identity: one logical reset per holding per date.
  String get dedupeKey => '$holdingKey@${date.toIso8601String()}';
}
