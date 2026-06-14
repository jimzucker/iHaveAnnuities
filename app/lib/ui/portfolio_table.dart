//
//  portfolio_table.dart
//  iHaveAnnuities
//
//  Copyright 2026 Jim Zucker
//  SPDX-License-Identifier: Apache-2.0
//
// Spreadsheet-style view that mirrors the Zucker Annuity Tracker columns, with
// per-row edit/delete and tap-to-open detail.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../core/payoff.dart';
import '../data/portfolio_store.dart';
import 'format.dart';
import 'holding_detail.dart';
import 'holding_form.dart';

class PortfolioTable extends StatelessWidget {
  const PortfolioTable({super.key});

  static const _headers = [
    'Position', 'Index Gain %', 'Proj Gain @ Reset', 'CAP', 'Part.', 'Floor',
    'Floor Type', 'Strike', 'Open', 'Last Reset', 'Maturity', 'Days to Mat.',
    'Reset Freq', 'Next Reset', 'Days to Reset', 'Initial (\$000)',
    'Realized (\$000)', 'Proj Value (\$000)', 'Proj \$ Gain (\$000)', 'Type',
    'Issuer', 'Index', '',
  ];

  @override
  Widget build(BuildContext context) {
    final store = context.watch<PortfolioStore>();
    final asOf = store.market?.asOf ?? DateTime(2026, 6, 14);
    final cs = Theme.of(context).colorScheme;

    return Scrollbar(
      thumbVisibility: true,
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStatePropertyAll(cs.primary),
            headingTextStyle: TextStyle(
                color: cs.onPrimary, fontWeight: FontWeight.w600, fontSize: 12),
            dataRowMinHeight: 40,
            dataRowMaxHeight: 48,
            columnSpacing: 22,
            columns: [
              for (final h in _headers) DataColumn(label: Text(h)),
            ],
            rows: [
              for (final x in store.holdings) _row(context, store, x, asOf, cs),
            ],
          ),
        ),
      ),
    );
  }

  DataRow _row(BuildContext context, PortfolioStore store, Holding x,
      DateTime asOf, ColorScheme cs) {
    DataCell t(String s) => DataCell(Text(s));
    DataCell signed(double v) =>
        DataCell(Text(pctSigned(v), style: TextStyle(color: gainColor(v, cs))));
    return DataRow(
      onSelectChanged: (_) => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => HoldingDetail(holding: x))),
      cells: [
        t(x.position),
        signed(x.indexGain),
        signed(x.projGain),
        t(capLabel(x.cap)),
        t(pct(x.participation)),
        t(x.floor == 0 ? '0.00%' : pct(x.floor)),
        DataCell(_pill(x.floorType == FloorType.soft ? 'Soft' : 'Hard',
            x.floorType == FloorType.soft ? const Color(0xFFFFF3E0) : const Color(0xFFEAF7EC),
            x.floorType == FloorType.soft ? const Color(0xFFB26A00) : const Color(0xFF0A7D28))),
        t(level(x.strike)),
        t(date(x.openDate)),
        t(date(x.lastReset)),
        t(date(x.maturity)),
        t('${x.daysToMaturity(asOf)}'),
        t(x.resetFreq.label),
        t(date(x.nextReset)),
        t('${x.daysToReset(asOf)}'),
        t(money000(x.initial)),
        t(money000(x.realized)),
        t(money000(x.projValueK)),
        DataCell(Text(money000(x.projGainDollarsK),
            style: TextStyle(color: gainColor(x.projGainDollarsK, cs)))),
        DataCell(_pill(x.account.label, cs.secondaryContainer, cs.onSecondaryContainer)),
        t(x.issuer),
        t(x.index),
        DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit, size: 18),
            onPressed: () => _edit(context, store, x),
          ),
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline, size: 18),
            onPressed: () => _delete(context, store, x),
          ),
        ])),
      ],
    );
  }

  Widget _pill(String text, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
        child: Text(text, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600)),
      );

  Future<void> _edit(BuildContext context, PortfolioStore store, Holding x) async {
    final edited = await Navigator.of(context)
        .push<Holding>(MaterialPageRoute(builder: (_) => HoldingForm(initial: x)));
    if (edited != null) await store.upsert(edited, replacing: x);
  }

  Future<void> _delete(BuildContext context, PortfolioStore store, Holding x) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete holding?'),
        content: Text(x.position),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) await store.remove(x);
  }
}
