// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: Apache-2.0
// Drill-down for one holding: a highlighted key-figures banner, the payoff
// chart, and the full terms grouped into readable section cards that reflow to
// fill the screen.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models.dart';
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
          _KeyFigures(h: h, cs: cs),
          const SizedBox(height: 12),
          Card(child: Padding(padding: const EdgeInsets.all(16), child: PayoffChart(holding: h))),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _Section(title: 'Terms', rows: [
                ('Issuer', h.issuer, null),
                ('Index', h.index, null),
                ('Account', h.account.label, null),
                ('Cap', capLabel(h.cap), null),
                ('Participation', pct(h.participation), null),
                ('Protection', _protection(h), null),
                if (h.isIncomeNote) ('Income note', 'coupon ${pct(h.couponProj)}', null),
              ]),
              _Section(title: 'Levels', rows: [
                ('Strike', level(h.strike), null),
                ('Current level', level(h.currentLevel), null),
                ('Index gain', pctSigned(h.indexGain), gainColor(h.indexGain, cs)),
              ]),
              _Section(title: 'Schedule', rows: [
                ('Open', date(h.openDate), null),
                ('Last reset', date(h.lastReset), null),
                ('Maturity', '${date(h.maturity)}  ·  ${h.daysToMaturity(asOf)}d', null),
                ('Reset freq', h.resetFreq.label, null),
                ('Next reset', '${date(h.nextReset)}  ·  ${h.daysToReset(asOf)}d', null),
              ]),
              _Section(title: 'Values (\$000)', rows: [
                ('Initial', money000(h.initial), null),
                ('Realized', money000(h.realized), null),
                ('Proj value @ reset', money000(h.projValueK), cs.primary),
                ('Proj \$ gain @ reset', money000(h.projGainDollarsK), gainColor(h.projGainDollarsK, cs)),
              ]),
            ],
          ),
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
    return Card(
      color: cs.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(spacing: 32, runSpacing: 12, children: [
          fig('Proj value @ reset', money000(h.projValueK), cs.onPrimaryContainer),
          fig('Proj \$ gain', money000(h.projGainDollarsK), gainColor(h.projGainDollarsK, cs)),
          fig('Payoff return', pctSigned(h.projGain), gainColor(h.projGain, cs)),
          fig('Index gain', pctSigned(h.indexGain), gainColor(h.indexGain, cs)),
        ]),
      ),
    );
  }
}

/// A titled card holding aligned label/value rows; an optional color highlights
/// the value.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.rows});
  final String title;
  final List<(String, String, Color?)> rows;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return SizedBox(
      width: 320,
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
                      child: Text(label, style: tt.bodyMedium?.copyWith(color: Colors.grey)),
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
