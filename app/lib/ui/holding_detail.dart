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
import 'payoff_chart.dart';

class HoldingDetail extends StatelessWidget {
  const HoldingDetail({super.key, required this.holding});
  final Holding holding;

  String _protection(Holding h) => h.floor == 0
      ? 'Protected (0% floor — no loss)'
      : (h.protectionType == 'Soft'
          ? 'Soft barrier ${pct(h.floor)}'
          : 'Hard buffer ${pct(h.floor)}');

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
  String _chartCaption(Holding h) {
    final state = switch (h.gainStatus) {
      GainStatus.capped => 'cap reached',
      GainStatus.loss => 'in loss',
      GainStatus.flat => 'flat',
      GainStatus.gain => 'gaining',
    };
    return 'Payoff at reset vs. the index move. Today the index is '
        '${pctSigned(h.indexGain)} → you would receive ${pctSigned(h.projGain)} '
        '($state).';
  }

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
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(_summary(h, asOf),
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(height: 1.4)),
          ),
          _KeyFigures(h: h, cs: cs),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                PayoffChart(holding: h),
                const SizedBox(height: 8),
                Text(_chartCaption(h),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant, height: 1.35)),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (context, c) {
            // Two columns that fill the width on wide screens; one on phones.
            final w = c.maxWidth >= 680 ? (c.maxWidth - 12) / 2 : c.maxWidth;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
              _Section(width: w, title: 'Terms', rows: [
                ('Issuer', h.issuer, null),
                ('Index', h.index, null),
                ('Account', h.account.label, null),
                ('Cap', capLabel(h.cap), null),
                ('Participation', pct(h.participation), null),
                ('Protection', _protection(h), null),
                if (h.isIncomeNote) ('Income note', 'coupon ${pct(h.couponProj)}', null),
              ]),
              _Section(width: w, title: 'Levels', rows: [
                ('Strike', level(h.strike), null),
                ('Current level', level(h.currentLevel), null),
                ('Index gain', pctSigned(h.indexGain), gainColor(h.indexGain, cs)),
              ]),
              _Section(width: w, title: 'Schedule', rows: [
                ('Open', date(h.openDate), null),
                ('Last reset', date(h.lastReset), null),
                ('Maturity', '${date(h.maturity)}  ·  ${relDays(h.daysToMaturity(asOf))}', null),
                ('Reset freq', h.resetFreq.label, null),
                ('Next reset', '${date(h.nextReset)}  ·  ${relDays(h.daysToReset(asOf))}', null),
              ]),
              _Section(width: w, title: 'Values', rows: [
                ('Initial', moneyK(h.initial), null),
                ('Realized', moneyK(h.realized), null),
                ('Proj value @ reset', moneyK(h.projValueK), cs.primary),
                ('Unrealized \$', moneyK(h.projGainDollarsK), gainColor(h.projGainDollarsK, cs)),
              ]),
            ],
            );
          }),
        ],
      ),
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
    final tt = Theme.of(context).textTheme;
    Widget fig(String label, String value, Color color) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: tt.labelMedium?.copyWith(color: cs.onPrimaryContainer)),
            Text(value, style: tt.headlineSmall?.copyWith(color: color, fontWeight: FontWeight.bold)),
          ],
        );
    Widget chip(String text, Color bg, Color fg) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
          child: Text(text,
              style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600)),
        );
    final prot = protectionPalette(h.protectionType, cs);
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
          const SizedBox(height: 12),
          Wrap(spacing: 32, runSpacing: 12, children: [
            fig('Proj value @ reset', moneyK(h.projValueK), cs.onPrimaryContainer),
            fig('Unrealized \$', moneyK(h.projGainDollarsK), gainColor(h.projGainDollarsK, cs)),
            fig('Payoff return', pctSigned(h.projGain), gainColor(h.projGain, cs)),
          ]),
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
