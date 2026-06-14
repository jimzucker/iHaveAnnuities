//
//  holding_detail.dart
//  iHaveAnnuities
//
//  Copyright 2026 Jim Zucker
//  SPDX-License-Identifier: Apache-2.0

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

  String get _protection {
    if (holding.floor == 0) return 'Floor (0%)';
    return holding.floorType == FloorType.soft
        ? 'Soft barrier ${pct(holding.floor)}'
        : 'Hard buffer ${pct(holding.floor)}';
  }

  @override
  Widget build(BuildContext context) {
    final store = context.read<PortfolioStore>();
    final asOf = store.market?.asOf ?? DateTime(2026, 6, 14);
    final cs = Theme.of(context).colorScheme;
    final h = holding;
    return Scaffold(
      appBar: AppBar(title: Text(h.position), actions: [
        IconButton(
          icon: const Icon(Icons.edit),
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
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Projected value @ reset',
                    style: Theme.of(context).textTheme.labelMedium),
                Text(moneyK(h.projValueK),
                    style: Theme.of(context).textTheme.headlineMedium),
                Text('${pctSigned(h.projGain)} payoff   ·   ${pctSigned(h.indexGain)} index',
                    style: TextStyle(color: gainColor(h.projGain, cs))),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          Card(child: Padding(padding: const EdgeInsets.all(16), child: PayoffChart(holding: h))),
          const SizedBox(height: 8),
          _row('Issuer', h.issuer),
          _row('Index', h.index),
          _row('Account', h.account.label),
          _row('Cap', capLabel(h.cap)),
          _row('Participation', pct(h.participation)),
          _row('Protection', _protection),
          _row('Strike', level(h.strike)),
          _row('Current level', level(h.currentLevel)),
          _row('Open', date(h.openDate)),
          _row('Last reset', date(h.lastReset)),
          _row('Maturity', '${date(h.maturity)}  (${h.daysToMaturity(asOf)} days)'),
          _row('Reset freq', h.resetFreq.label),
          _row('Next reset', '${date(h.nextReset)}  (${h.daysToReset(asOf)} days)'),
          _row('Initial', moneyK(h.initial)),
          _row('Realized', moneyK(h.realized)),
          if (h.isIncomeNote) _row('Income note', 'coupon ${pct(h.couponProj)}'),
        ],
      ),
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(k, style: const TextStyle(color: Colors.grey)),
          Flexible(child: Text(v, textAlign: TextAlign.right)),
        ]),
      );
}
