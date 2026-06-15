// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

final _money = NumberFormat.currency(symbol: '\$', decimalDigits: 0);
final _date = DateFormat('dd-MMM-yyyy');
final _level = NumberFormat('#,##0.00');

/// $000 value → full-dollar currency string.
String moneyK(double thousands) => _money.format(thousands * 1000);

/// $000 value shown as-is (matches the xls "$ in $000s" columns), e.g. $112.25.
String money000(double v) => '\$${_level.format(v)}';
String pct(double v) => '${(v * 100).toStringAsFixed(2)}%';
String pctSigned(double v) =>
    '${v > 0 ? '+' : ''}${(v * 100).toStringAsFixed(2)}%';
String level(double v) => _level.format(v);
String date(DateTime d) => _date.format(d);
String capLabel(double? cap) => cap == null ? 'Uncapped' : pct(cap);

Color gainColor(double v, ColorScheme c) =>
    v > 0 ? const Color(0xFF0A7D28) : (v < 0 ? const Color(0xFFB00020) : c.onSurfaceVariant);
