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
        ? '${pct(h.couponRate)} monthly coupon'
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
        PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'recalc') _recalc(context, store, h);
          },
          itemBuilder: (_) => [
            const PopupMenuItem(
              value: 'recalc',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.restart_alt),
                title: Text('Recompute from start'),
                subtitle: Text('Replay every reset from the open date'),
              ),
            ),
          ],
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
          _KeyFigures(h: h, cs: cs, asOf: asOf),
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

  /// Confirm, then replay the contract from its open date (overwrites the
  /// drifted realized/strike and this contract's reset-history entries).
  Future<void> _recalc(
      BuildContext context, PortfolioStore store, Holding h) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Recompute from start?'),
        content: const Text(
            'This replays every reset from the open date using market history, '
            'overwriting the current realized amount, strike, and this '
            'contract’s reset-history entries. The originals can’t be restored.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Recompute')),
        ],
      ),
    );
    if (ok != true) return;
    final n = await store.recalcFromStart(h);
    messenger.showSnackBar(SnackBar(
      content: Text(n < 0
          ? (store.status ?? 'History unavailable; could not recompute.')
          : 'Recomputed from start — $n reset${n == 1 ? '' : 's'} replayed.'),
    ));
  }

  Widget _chartCard(BuildContext context, Holding h, String base) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: IndexPeriodChart(holding: h, base: base),
        ),
      );

  // Only the Schedule (dates) lives beside the chart now — the figures and the
  // contract terms moved into the unified header, so nothing is duplicated.
  Widget _sections(BuildContext context, Holding h, DateTime asOf, ColorScheme cs) =>
      _Section(width: double.infinity, title: 'Schedule', rows: [
        ('Open', date(h.openDate), null),
        ('Last Reset', date(h.lastReset), null),
        ('Maturity', '${date(h.maturity)}  ·  ${relDays(h.daysToMaturity(asOf))}', null),
        ('Reset Freq', h.resetFreq.label, null),
        ('Next Reset', '${date(h.nextReset)}  ·  ${relDays(h.daysToReset(asOf))}', null),
      ]);
}

/// Unified header: a top tier of big outcome figures and a second tier of the
/// contract terms/levels (folded in from the former grey strip), so everything
/// lives in one card with no duplicated figures.
class _KeyFigures extends StatelessWidget {
  const _KeyFigures({required this.h, required this.cs, required this.asOf});
  final Holding h;
  final ColorScheme cs;
  final DateTime asOf;

  @override
  Widget build(BuildContext context) {
    final onC = cs.onPrimaryContainer;
    final muted = onC.withValues(alpha: 0.75);
    // Tier 1: big outcome figures (dollars read as a sum, then the percentages).
    Widget fig(String label, String value, Color color) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 12, color: muted)),
            Text(value,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
          ],
        );
    // Tier 2: contract terms/levels (a notch smaller than the figures).
    Widget term(String label, String value, {Color? color}) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 12, color: muted)),
            Text(value,
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600, color: color ?? onC)),
          ],
        );
    Widget chip(String text, Color bg, Color fg) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
          child: Text(text,
              style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600)),
        );
    final prot = protectionPalette(h.protectionType, cs);
    final figs = <Widget>[
      fig('Initial', moneyK(h.initial), onC),
      fig('Realized', moneyK(h.realized), onC),
      fig('Unrealized \$', moneyK(h.projGainDollarsK), gainColor(h.projGainDollarsK, cs)),
      fig('Projected Value', moneyK(h.projValueK), onC),
      fig('Unrealized %', pctSigned(h.projGain), gainColor(h.projGain, cs)),
      fig('Index Gain', pctSigned(h.indexGain), gainColor(h.indexGain, cs)),
    ];
    // Always show the floor level alongside the type (e.g. "Floor 0.00%").
    final protLabel = '${h.protectionType} ${pct(h.floor)}';
    final terms = <Widget>[
      term('Account', h.account.label),
      term('Index', h.index),
      term('Cap', capLabel(h.cap)),
      term('Participation', pct(h.participation)),
      term('Protection', protLabel),
      term('Strike', level(h.strike)),
      term('Current', level(h.currentLevel)),
      if (h.isIncomeNote) term('Coupon', pct(h.couponRate)),
    ];
    return Card(
      color: cs.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 8, runSpacing: 6, children: [
            chip(h.protectionType, prot.bg, prot.fg),
            // Flag the cap only when it's actually reached (matches the table).
            if (h.gainStatus == GainStatus.capped)
              chip('${capLabel(h.cap)} cap reached',
                  const Color(0xFFFFF3E0), capAmber),
          ]),
          const SizedBox(height: 14),
          // Equal-width columns (not spaceBetween, which flings the first/last
          // items to the edges with uneven gaps); content left-aligns at evenly
          // spaced column starts, reading as a tidy stat grid.
          LayoutBuilder(builder: (context, c) {
            return c.maxWidth >= 700
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [for (final f in figs) Expanded(child: f)])
                : Wrap(spacing: 28, runSpacing: 12, children: figs);
          }),
          Divider(height: 26, color: onC.withValues(alpha: 0.20)),
          LayoutBuilder(builder: (context, c) {
            return c.maxWidth >= 700
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [for (final t in terms) Expanded(child: t)])
                : Wrap(spacing: 24, runSpacing: 14, children: terms);
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
