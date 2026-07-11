// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: LicenseRef-Proprietary

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/models.dart';

final _money = NumberFormat.currency(symbol: '\$', decimalDigits: 0);
final _date = DateFormat('dd-MMM-yy');
final _stamp = DateFormat('yyyyMMdd');
final _level = NumberFormat('#,##0.00');

/// Filename (no extension) for a data export, dated so copies don't clobber and
/// sort chronologically: `export_ihaveannuities_YYYYMMDD`. [on] defaults to today.
String exportFileName({DateTime? on}) =>
    'export_ihaveannuities_${_stamp.format(on ?? DateTime.now())}';

/// $000 value → full-dollar currency string.
String moneyK(double thousands) => _money.format(thousands * 1000);

/// $000 value shown as-is (matches the xls "$ in $000s" columns), e.g. $112.25.
String money000(double v) => '\$${_level.format(v)}';
String pct(double v) => '${(v * 100).toStringAsFixed(2)}%';
String pctSigned(double v) =>
    '${v > 0 ? '+' : ''}${(v * 100).toStringAsFixed(2)}%';
String level(double v) => _level.format(v);
String date(DateTime d) => _date.format(d);

/// Relative day count: "in 325 days" / "12 days ago" / "today".
String relDays(int d) =>
    d == 0 ? 'today' : (d > 0 ? 'in $d days' : '${-d} days ago');
String capLabel(double? cap) => cap == null ? 'Uncapped' : pct(cap);

/// Compact index label for tables/headers: drops a leading "worst-of " (the
/// worst-of nature is conveyed in the summary), so the basket fits a column
/// instead of ballooning it. e.g. "worst-of SPX/NDX/RUT" → "SPX/NDX/RUT".
String indexLabel(String index) =>
    index.replaceFirst(RegExp(r'^\s*worst[- ]of\s+', caseSensitive: false), '');

// Semantic gain/loss colors — reference these everywhere instead of ad-hoc hex.
const gainGreen = Color(0xFF0A7D28);
const lossRed = Color(0xFFB00020);
// Brighter variants for sufficient contrast on dark surfaces.
const _gainGreenDark = Color(0xFF4ADE80);
const _lossRedDark = Color(0xFFFF6B6B);

Color gainColor(double v, ColorScheme c) {
  if (v == 0) return c.onSurfaceVariant;
  final dark = c.brightness == Brightness.dark;
  return v > 0 ? (dark ? _gainGreenDark : gainGreen) : (dark ? _lossRedDark : lossRed);
}

/// Color only the EXCEPTION: red for a loss, neutral otherwise — so losses
/// stand out instead of every positive row being green.
Color lossColor(double v, ColorScheme c) => v < 0
    ? (c.brightness == Brightness.dark ? _lossRedDark : lossRed)
    : c.onSurface;

// "Cap reached" amber — a positive gain that has hit its ceiling.
const capAmber = Color(0xFFB26A00);
const _capAmberDark = Color(0xFFE0A030);

/// Color for the upside status — only the exceptions are colored (red loss,
/// amber capped); a routine gain is neutral so it doesn't wash the table green.
Color gainStatusColor(GainStatus s, ColorScheme c) {
  final dark = c.brightness == Brightness.dark;
  return switch (s) {
    GainStatus.loss => dark ? _lossRedDark : lossRed,
    GainStatus.capped => dark ? _capAmberDark : capAmber,
    GainStatus.gain => c.onSurface,
    GainStatus.flat => c.onSurfaceVariant,
  };
}

/// Single source of truth for protection-type colors: a pill background/
/// foreground pair plus a solid accent. Used by the table pill, the detail
/// view, and the info page so the three never drift apart.
({Color bg, Color fg, Color accent}) protectionPalette(
        String type, ColorScheme cs) =>
    switch (type) {
      'Soft' => (
          bg: const Color(0xFFFFF3E0),
          fg: const Color(0xFFB26A00),
          accent: const Color(0xFFB26A00),
        ),
      'Floor' => (
          bg: const Color(0xFFE6EFFF),
          fg: const Color(0xFF1F3A5F),
          accent: cs.primary,
        ),
      'None' => (
          bg: const Color(0xFFFBE4E6),
          fg: const Color(0xFFB00020),
          accent: const Color(0xFFB00020),
        ),
      _ => (bg: const Color(0xFFEAF7EC), fg: gainGreen, accent: gainGreen),
    };
