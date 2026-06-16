// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: Apache-2.0
// Drill-down for one holding: a highlighted key-figures banner, the payoff
// chart, and the full terms grouped into readable section cards that reflow to
// fill the screen.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../core/payoff.dart';
import '../data/portfolio_store.dart';
import 'format.dart';
import 'holding_form.dart';
import 'index_period_chart.dart';

class HoldingDetail extends StatelessWidget {
  const HoldingDetail({super.key, required this.holding});
  final Holding holding;

  /// One plain-English sentence describing the contract.
  String _summary(Holding h, DateTime asOf) {
    final cap = h.cap == null ? 'uncapped' : 'capped at ${pct(h.cap!)}';
    final part = h.participation == 1.0 ? '' : ' at ${pct(h.participation)} participation';
    final down = h.floor == 0
        ? 'no loss if it falls'
        : (h.floorType == FloorType.soft
            ? 'protected unless it falls past ${pct(h.floor.abs())} (then full loss)'
            : 'a ${pct(h.floor.abs())} buffer absorbs the first losses');
    final upside = h.isIncomeNote
        ? '${pct(h.couponProj)} monthly coupon'
        : 'gains $cap$part';
    return '${h.index}-linked — $upside, with $down. Resets '
        '${h.resetFreq.label.toLowerCase()}; next reset ${date(h.nextReset)} '
        '(${relDays(h.daysToReset(asOf))}).';
  }

  /// Plain-English read of where it stands today.
  @override
  Widget build(BuildContext context) {
    final store = context.read<PortfolioStore>();
    final asOf = store.market?.asOf ?? DateTime(2026, 6, 14);
    final cs = Theme.of(context).colorScheme;
    final h = holding;

    return Scaffold(
      appBar: AppBar(title: Text(store.labelFor(h)), actions: [
        IconButton(
          icon: const Icon(Icons.edit),
          tooltip: 'Edit',
          onPressed: () async {
            final edited = await Navigator.of(context).push<Holding>(
                MaterialPageRoute(builder: (_) => HoldingForm(initial: h)));
            if (edited != null) {
              await store.upsert(edited, replacing: h);
              if (context.mounted) Navigator.of(context).pop();
            }
          },
        ),
      ]),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(_summary(h, asOf),
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.4)),
          ),
          _KeyFigures(h: h, cs: cs),
          const SizedBox(height: 10),
          _keyStrip(context, h, asOf), // compact scannable line of key facts
          const SizedBox(height: 12),
          // Wide screens: chart and the fact cards side by side (everything
          // above the fold). Narrow: stacked.
          LayoutBuilder(builder: (context, c) {
            final chart = _chartCard(context, h, store.base);
            final sections = _sections(context, h, asOf, cs);
            if (c.maxWidth >= 960) {
              return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(flex: 3, child: chart),
                const SizedBox(width: 12),
                Expanded(flex: 2, child: sections),
              ]);
            }
            return Column(children: [chart, const SizedBox(height: 12), sections]);
          }),
        ],
      ),
    );
  }

  Widget _chartCard(BuildContext context, Holding h, String base) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: IndexPeriodChart(holding: h, base: base),
        ),
      );

  Widget _sections(BuildContext context, Holding h, DateTime asOf, ColorScheme cs) =>
      LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth >= 540 ? (c.maxWidth - 12) / 2 : c.maxWidth;
        return Wrap(spacing: 12, runSpacing: 12, children: [
          _Section(width: w, title: 'Schedule', rows: [
            ('Open', date(h.openDate), null),
            ('Last Reset', date(h.lastReset), null),
            ('Maturity', '${date(h.maturity)}  ·  ${relDays(h.daysToMaturity(asOf))}', null),
            ('Reset Freq', h.resetFreq.label, null),
            ('Next Reset', '${date(h.nextReset)}  ·  ${relDays(h.daysToReset(asOf))}', null),
          ]),
          _Section(width: w, title: 'Values', rows: [
            ('Initial', moneyK(h.initial), null),
            ('Realized', moneyK(h.realized), null),
            ('Projected Value', moneyK(h.projValueK), cs.primary),
            ('Unrealized \$', moneyK(h.projGainDollarsK), gainColor(h.projGainDollarsK, cs)),
            ('Unrealized %', pctSigned(h.projGain), gainColor(h.projGain, cs)),
            if (h.isIncomeNote) ('Income note', 'coupon ${pct(h.couponProj)}', null),
          ]),
        ]);
      });

  /// Compact, scannable strip of the key terms/levels (mirrors the compact
  /// table view) so the critical info is visible without scrolling.
  Widget _keyStrip(BuildContext context, Holding h, DateTime asOf) {
    final cs = Theme.of(context).colorScheme;
    final prot = h.floor == 0 ? 'Protected' : '${h.protectionType} ${pct(h.floor)}';
    Widget kv(String k, String v, {Color? color}) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(k, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
            Text(v,
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600, color: color)),
          ],
        );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10)),
      child: Wrap(spacing: 24, runSpacing: 10, children: [
        kv('Account', h.account.label),
        kv('Index', h.index),
        kv('Cap', capLabel(h.cap)),
        kv('Participation', pct(h.participation)),
        kv('Protection', prot),
        kv('Strike', level(h.strike)),
        kv('Current', level(h.currentLevel)),
        kv('Index Gain', pctSigned(h.indexGain), color: gainColor(h.indexGain, cs)),
        kv('Next Reset', '${date(h.nextReset)} · ${relDays(h.daysToReset(asOf))}'),
      ]),
    );
  }
}

/// Big highlighted key figures.
class _KeyFigures extends StatelessWidget {
  const _KeyFigures({required this.h, required this.cs});
  final Holding h;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final onC = cs.onPrimaryContainer;
    Widget fig(String label, String value, Color color) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(fontSize: 12, color: onC.withValues(alpha: 0.85))),
            Text(value,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
          ],
        );
    Widget chip(String text, Color bg, Color fg) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
          child: Text(text,
              style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600)),
        );
    final prot = protectionPalette(h.protectionType, cs);
    // Consistent grid labels (no ad-hoc "Payoff return"); spread across the
    // width so the banner reads like a stat row in the main grid.
    final figs = <Widget>[
      fig('Projected Value', moneyK(h.projValueK), onC),
      fig('Unrealized \$', moneyK(h.projGainDollarsK), gainColor(h.projGainDollarsK, cs)),
      fig('Unrealized %', pctSigned(h.projGain), gainColor(h.projGain, cs)),
      fig('Index Gain', pctSigned(h.indexGain), gainColor(h.indexGain, cs)),
      fig('Initial', moneyK(h.initial), onC),
      fig('Realized', moneyK(h.realized), onC),
    ];
    return Card(
      color: cs.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 8, runSpacing: 6, children: [
            chip(h.protectionType, prot.bg, prot.fg),
            if (h.gainStatus == GainStatus.capped)
              chip('${capLabel(h.cap)} cap reached',
                  const Color(0xFFFFF3E0), capAmber),
            if (h.gainStatus == GainStatus.gain && h.hasCap)
              chip('Below the ${capLabel(h.cap)} cap',
                  const Color(0xFFEAF7EC), gainGreen),
          ]),
          const SizedBox(height: 14),
          LayoutBuilder(builder: (context, c) {
            return c.maxWidth >= 700
                ? Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: figs)
                : Wrap(spacing: 28, runSpacing: 12, children: figs);
          }),
        ]),
      ),
    );
  }
}

/// A titled card holding aligned label/value rows; an optional color highlights
/// the value.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.rows, this.width = 320});
  final String title;
  final List<(String, String, Color?)> rows;
  final double width;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return SizedBox(
      width: width,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: tt.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
            const Divider(),
            Table(
              columnWidths: const {0: IntrinsicColumnWidth(), 1: FlexColumnWidth()},
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                for (final (label, value, color) in rows)
                  TableRow(children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 0),
                      child: Text(label,
                          style: tt.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 16, top: 5, bottom: 5),
                      child: Text(
                        value,
                        textAlign: TextAlign.right,
                        style: tt.bodyMedium?.copyWith(
                            color: color,
                            fontWeight: color == null ? FontWeight.normal : FontWeight.bold),
                      ),
                    ),
                  ]),
              ],
            ),
          ]),
        ),
      ),
    );
  }
}
