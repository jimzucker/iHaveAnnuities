// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: Apache-2.0
// A summary band above the table: a protection-mix donut (principal split
// across Floor / Hard-buffer / Soft-buffer), a projected-gain bar, and the soonest
// upcoming resets. Replaces the plain stats row.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../data/portfolio_store.dart';
import 'format.dart';

class PortfolioHero extends StatelessWidget {
  const PortfolioHero({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<PortfolioStore>();
    final cs = Theme.of(context).colorScheme;
    final asOf = store.market?.asOf ?? DateTime(2026, 6, 14);

    // Principal by protection type.
    final mix = <String, double>{'Floor': 0, 'Hard-buffer': 0, 'Soft-buffer': 0};
    for (final h in store.holdings) {
      mix[h.protectionType] = (mix[h.protectionType] ?? 0) + h.initial;
    }

    // Soonest upcoming resets.
    final upcoming = [...store.holdings]
      ..sort((a, b) => a.daysToReset(asOf).compareTo(b.daysToReset(asOf)));

    return Container(
      width: double.infinity,
      color: cs.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Wrap(
        spacing: 24,
        runSpacing: 12,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _ProtectionDonut(mix: mix, total: store.totalInitial, cs: cs),
          _ProjectedBlock(store: store, cs: cs),
          _NextResets(upcoming: upcoming, asOf: asOf, store: store, cs: cs),
        ],
      ),
    );
  }
}

class _ProtectionDonut extends StatelessWidget {
  const _ProtectionDonut({required this.mix, required this.total, required this.cs});
  final Map<String, double> mix;
  final double total;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final entries = mix.entries.where((e) => e.value > 0).toList();
    return Row(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        width: 64,
        height: 64,
        child: CustomPaint(
          painter: _DonutPainter(
            [for (final e in entries) (protectionPalette(e.key, cs).accent, e.value)],
            cs.surfaceContainerHighest,
          ),
        ),
      ),
      const SizedBox(width: 12),
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Protection',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          for (final e in entries)
            _legend(e.key, e.value, total, protectionPalette(e.key, cs).accent),
        ],
      ),
    ]);
  }

  Widget _legend(String label, double v, double total, Color c) {
    final pctText = total <= 0 ? '' : '  ${(v / total * 100).round()}%';
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 9, height: 9, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text('$label$pctText', style: const TextStyle(fontSize: 12)),
      ]),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.slices, this.trackColor);
  final List<(Color, double)> slices;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final total = slices.fold(0.0, (s, e) => s + e.$2);
    final rect = Rect.fromLTWH(6, 6, size.width - 12, size.height - 12);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.butt;
    // Track.
    canvas.drawArc(rect, 0, 2 * math.pi, false, stroke..color = trackColor);
    if (total <= 0) return;
    var start = -math.pi / 2;
    for (final (color, value) in slices) {
      final sweep = value / total * 2 * math.pi;
      canvas.drawArc(rect, start, sweep - 0.04, false, stroke..color = color);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) => old.slices != slices;
}

class _ProjectedBlock extends StatelessWidget {
  const _ProjectedBlock({required this.store, required this.cs});
  final PortfolioStore store;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final gain = store.totalProjGain;
    final pct = store.totalInitial <= 0 ? 0.0 : gain / store.totalInitial;
    final gc = gainColor(gain, cs);
    Widget kpi(String label, Widget value) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            value,
            Text(label, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          ],
        );
    const big = TextStyle(fontSize: 22, fontWeight: FontWeight.bold);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${store.holdings.length} contracts',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        const SizedBox(height: 6),
        // The two headline totals, large and meaningfully colored.
        Wrap(spacing: 32, runSpacing: 8, children: [
          kpi(
            'Total Value',
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: store.totalProjValue),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (_, v, _) => Text(moneyK(v), style: big),
            ),
          ),
          kpi(
            'Total Unrealized G/L',
            Text('${gain >= 0 ? '▲' : '▼'} ${moneyK(gain)}  (${pctSigned(pct)})',
                style: big.copyWith(color: gc)),
          ),
        ]),
        const SizedBox(height: 8),
        SizedBox(width: 240, child: _GainBar(pct: pct, color: gc)),
        const SizedBox(height: 6),
        Text(
            'Principal ${moneyK(store.totalInitial)}   ·   '
            'Realized ${moneyK(store.totalRealized)}',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
      ],
    );
  }
}

class _GainBar extends StatelessWidget {
  const _GainBar({required this.pct, required this.color});
  final double pct;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Map gain% onto a bar around a center baseline (±50% full scale).
    final frac = (pct.abs() / 0.5).clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Container(
        height: 8,
        color: cs.surfaceContainerLow,
        child: Align(
          alignment: pct >= 0 ? Alignment.centerLeft : Alignment.centerRight,
          child: FractionallySizedBox(
            widthFactor: frac == 0 ? 0.02 : frac,
            child: Container(color: color),
          ),
        ),
      ),
    );
  }
}

class _NextResets extends StatelessWidget {
  const _NextResets(
      {required this.upcoming, required this.asOf, required this.store, required this.cs});
  final List<Holding> upcoming;
  final DateTime asOf;
  final PortfolioStore store;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final top = upcoming.take(3).toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Next resets', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        const SizedBox(height: 2),
        for (final h in top)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text.rich(TextSpan(children: [
              TextSpan(
                  text: '${h.daysToReset(asOf)}d ',
                  style: TextStyle(fontWeight: FontWeight.bold, color: cs.primary)),
              TextSpan(text: '${store.labelFor(h)} · ${date(h.nextReset)}'),
            ]), style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
          ),
      ],
    );
  }
}
