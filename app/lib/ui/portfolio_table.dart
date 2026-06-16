// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: Apache-2.0
// Spreadsheet-style view mirroring the Zucker Annuity Tracker columns. Every
// column is sortable; the chosen sort is remembered (PortfolioStore), defaulting
// to Next Reset ascending. Per-row edit/delete; tap a row to drill in.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../data/portfolio_store.dart';
import 'format.dart';
import 'holding_detail.dart';
import 'holding_form.dart';

/// One sortable column: how to render it and how to sort by it.
class _Col {
  const _Col(this.label, this.numeric, this.key, this.cell);
  final String label;
  final bool numeric;
  final Comparable Function(Holding h, DateTime asOf) key;
  final DataCell Function(Holding h, DateTime asOf, ColorScheme cs) cell;
}

class PortfolioTable extends StatelessWidget {
  const PortfolioTable({super.key});

  static DataCell _t(String s) => DataCell(Text(s));
  static DataCell _signed(double v, ColorScheme cs) =>
      DataCell(Text(pctSigned(v), style: TextStyle(color: gainColor(v, cs))));

  static Widget _pill(String text, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
        child: Text(text, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600)),
      );

  // v1.1 order: Identity → Outcome → Terms → Schedule → Inputs.
  static List<_Col> _columns(ColorScheme cs) => [
        // Identity
        _Col('Issuer', false, (h, _) => h.issuer.toLowerCase(), (h, _, _) => _t(h.issuer)),
        _Col('Type', false, (h, _) => h.account.label, (h, _, cs) =>
            DataCell(_pill(h.account.label, cs.secondaryContainer, cs.onSecondaryContainer))),
        _Col('Index', false, (h, _) => h.index.toLowerCase(), (h, _, _) => _t(h.index)),
        _Col('Floor Type', false, (h, _) => h.protectionType, (h, _, cs) {
          final p = h.protectionType;
          final c = protectionPalette(p, cs);
          return DataCell(_pill(p, c.bg, c.fg));
        }),
        // Outcome
        _Col('Proj Value @ Reset (\$000)', true, (h, _) => h.projValueK, (h, _, _) => _t(money000(h.projValueK))),
        _Col('Proj \$ Gain @ Reset (\$000)', true, (h, _) => h.projGainDollarsK,
            (h, _, cs) => DataCell(Text(money000(h.projGainDollarsK),
                style: TextStyle(color: gainColor(h.projGainDollarsK, cs))))),
        _Col('Proj Gain @ Reset', true, (h, _) => h.projGain, (h, _, cs) => _signed(h.projGain, cs)),
        _Col('Index Gain %', true, (h, _) => h.indexGain, (h, _, cs) => _signed(h.indexGain, cs)),
        // Terms
        _Col('CAP', true, (h, _) => h.cap ?? double.infinity, (h, _, _) => _t(capLabel(h.cap))),
        _Col('Part.', true, (h, _) => h.participation, (h, _, _) => _t(pct(h.participation))),
        _Col('Floor', true, (h, _) => h.floor, (h, _, _) => _t(h.floor == 0 ? '0.00%' : pct(h.floor))),
        _Col('Strike', true, (h, _) => h.strike, (h, _, _) => _t(level(h.strike))),
        // Schedule
        _Col('Next Reset', false, (h, _) => h.nextReset, (h, _, _) => _t(date(h.nextReset))),
        _Col('Days to Reset', true, (h, a) => h.daysToReset(a), (h, a, _) => _t('${h.daysToReset(a)}')),
        _Col('Maturity', false, (h, _) => h.maturity, (h, _, _) => _t(date(h.maturity))),
        _Col('Days to Maturity', true, (h, a) => h.daysToMaturity(a), (h, a, _) => _t('${h.daysToMaturity(a)}')),
        _Col('Reset Freq', false, (h, _) => h.resetFreq.index, (h, _, _) => _t(h.resetFreq.label)),
        _Col('Open', false, (h, _) => h.openDate, (h, _, _) => _t(date(h.openDate))),
        _Col('Last Reset', false, (h, _) => h.lastReset, (h, _, _) => _t(date(h.lastReset))),
        // Inputs
        _Col('Initial (\$000)', true, (h, _) => h.initial, (h, _, _) => _t(money000(h.initial))),
        _Col('Realized (\$000)', true, (h, _) => h.realized, (h, _, _) => _t(money000(h.realized))),
      ];

  @override
  Widget build(BuildContext context) {
    final store = context.watch<PortfolioStore>();
    final asOf = store.market?.asOf ?? DateTime(2026, 6, 14);
    final cs = Theme.of(context).colorScheme;
    final cols = _columns(cs);

    final sortIdx = store.sortColumn.clamp(0, cols.length - 1);
    final items = [...store.holdings];
    final keyer = cols[sortIdx].key;
    items.sort((a, b) {
      final r = keyer(a, asOf).compareTo(keyer(b, asOf));
      return store.sortAscending ? r : -r;
    });

    return Scrollbar(
      thumbVisibility: true,
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            sortColumnIndex: sortIdx,
            sortAscending: store.sortAscending,
            headingRowColor: WidgetStatePropertyAll(cs.primary),
            headingTextStyle: TextStyle(
                color: cs.onPrimary, fontWeight: FontWeight.w600, fontSize: 12),
            dataRowMinHeight: 40,
            dataRowMaxHeight: 48,
            columnSpacing: 22,
            columns: [
              for (final c in cols)
                DataColumn(
                  label: Text(c.label),
                  numeric: c.numeric,
                  onSort: (i, asc) => store.setSort(i, asc),
                ),
              const DataColumn(label: Text('')),
            ],
            rows: [
              for (final x in items)
                DataRow(
                  onSelectChanged: (_) => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => HoldingDetail(holding: x))),
                  cells: [
                    for (final c in cols) c.cell(x, asOf, cs),
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
                ),
            ],
          ),
        ),
      ),
    );
  }

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
        content: Text(store.labelFor(x)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) await store.remove(x);
  }
}
