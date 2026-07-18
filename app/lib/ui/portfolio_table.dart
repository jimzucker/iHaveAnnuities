// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: LicenseRef-Proprietary
// Spreadsheet-style view mirroring the Zucker Annuity Tracker columns. Every
// column is sortable; the chosen sort is remembered (PortfolioStore), defaulting
// to Next Reset ascending. Per-row edit/delete; tap a row to drill in.

import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../data/portfolio_store.dart';
import 'confirm.dart';
import 'format.dart';
import 'holding_detail.dart';
import 'holding_form.dart';

/// A shared-axis-style transition into a holding's detail view (fade + a small
/// upward slide), nicer than the default platform push.
Route<void> detailRoute(Holding h) => PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 280),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, _, _) => HoldingDetail(holding: h),
      transitionsBuilder: (_, anim, _, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.04), end: Offset.zero)
                .animate(curved),
            child: child,
          ),
        );
      },
    );

/// The weighted aggregates shown on a group/total band. Pure and testable so
/// the TOTAL row provably reconciles with the hero card: every figure uses the
/// same definition the hero does (dollars are sums; ratios divide by principal,
/// so Return% − Unrealized% = Realized%). Yield is money-weighted XIRR and is
/// supplied separately by the caller (store.xirrFor / portfolioXirr).
class BandAggregates {
  const BandAggregates({
    required this.initial,
    required this.realized,
    required this.projValue,
    required this.unrealizedDollars,
    required this.returnPct,
    required this.unrealizedPct,
    required this.indexGain,
  });

  final double initial, realized, projValue, unrealizedDollars;

  /// Null when there is no principal to divide by (an empty/zero group).
  final double? returnPct, unrealizedPct, indexGain;

  factory BandAggregates.of(Iterable<Holding> items) {
    var initial = 0.0, realized = 0.0, projValue = 0.0, idxWeighted = 0.0;
    for (final h in items) {
      initial += h.initial;
      realized += h.realized;
      projValue += h.projValueK;
      idxWeighted += h.indexGain * h.initial;
    }
    final unrealized = projValue - initial - realized;
    final hasBase = initial != 0;
    return BandAggregates(
      initial: initial,
      realized: realized,
      projValue: projValue,
      unrealizedDollars: unrealized,
      returnPct: hasBase ? (projValue - initial) / initial : null,
      unrealizedPct: hasBase ? unrealized / initial : null,
      indexGain: hasBase ? idxWeighted / initial : null,
    );
  }
}

/// One sortable column: how to render it and how to sort by it.
class _Col {
  const _Col(this.label, this.numeric, this.key, this.cell,
      {this.fixedWidth, this.tooltip});
  final String label;
  final bool numeric;
  final Comparable Function(Holding h, DateTime asOf) key;
  final DataCell Function(Holding h, DateTime asOf, ColorScheme cs) cell;

  /// When set, the column is exactly this wide (won't flex). Used to keep
  /// short numeric/code columns tight so the slack goes to names/dates/money.
  final double? fixedWidth;

  /// Optional header tooltip (hover/long-press) for columns whose short label
  /// drops nuance — e.g. "Total Value" is the value projected at the next reset.
  final String? tooltip;
}

class PortfolioTable extends StatelessWidget {
  const PortfolioTable({super.key});

  static DataCell _t(String s) => DataCell(Text(s));
  // Neutral unless it's a loss — keeps routine positives from washing the table
  // green so losses (red) and capped rows (amber) actually stand out.
  static DataCell _signed(double v, ColorScheme cs) =>
      DataCell(Text(pctSigned(v), style: TextStyle(color: lossColor(v, cs))));

  static Widget _pill(String text, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
        child: Text(text, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600)),
      );

  // v1.2 order: Identity → Inputs → Outcome → Timing (monitor) → Terms (static).
  // Labels are short (the header length, not the data, drove the column width);
  // money is shown in full dollars on screen ($ in $000s only in the .xlsx).
  static List<_Col> _columns(ColorScheme cs) => [
        // Identity
        // Issuer is styled as a link (underlined) to signal the row drills in.
        _Col('Issuer', false, (h, _) => h.issuer.toLowerCase(),
            (h, _, cs) => DataCell(Text(h.issuer,
                style: TextStyle(
                    color: cs.primary,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.underline,
                    decorationColor: cs.primary))),
            fixedWidth: 150),
        _Col('Type', false, (h, _) => h.account.label, (h, _, cs) =>
            DataCell(_pill(h.account.label, cs.secondaryContainer, cs.onSecondaryContainer)),
            fixedWidth: 88),
        _Col('Index', false, (h, _) => h.index.toLowerCase(),
            (h, _, _) => _t(indexLabel(h.index)),
            fixedWidth: 104),
        _Col('Protection', false, (h, _) => h.protectionType, (h, _, cs) {
          final p = h.protectionType;
          final c = protectionPalette(p, cs);
          return DataCell(_pill(p, c.bg, c.fg));
        }, fixedWidth: 104), // fits the "Protection" header on one line
        // Inputs
        _Col('Initial', true, (h, _) => h.initial, (h, _, _) => _t(moneyK(h.initial)),
            fixedWidth: 104),
        _Col('Realized', true, (h, _) => h.realized, (h, _, _) => _t(moneyK(h.realized)),
            fixedWidth: 104),
        // Outcome — the dollar columns read as a running sum
        // (Initial + Realized + Unrealized $ = Total Value), then Total Value's
        // all-in return %, with Unrealized % / Index Gain alongside it.
        _Col('Unrealized \$', true, (h, _) => h.projGainDollarsK,
            (h, _, cs) => DataCell(Text(moneyK(h.projGainDollarsK),
                style: TextStyle(color: lossColor(h.projGainDollarsK, cs)))),
            fixedWidth: 112),
        // "Total Value" = value projected at the next reset (today's levels);
        // the export keeps the precise "Proj Value @ Reset" label.
        _Col('Total Value', true, (h, _) => h.projValueK,
            (h, _, _) => _t(moneyK(h.projValueK)),
            fixedWidth: 120,
            tooltip: 'Value projected at the next reset, using today\'s index levels'),
        // All-in return on principal: (Total Value − Initial) / Initial.
        // Only losses are flagged red (matching Unrealized $ / Index Gain).
        _Col('Return %', true, (h, _) => h.totalReturnPct, (h, _, cs) => DataCell(
            Text(h.initial <= 0 ? '' : pctSigned(h.totalReturnPct),
                style: TextStyle(color: lossColor(h.totalReturnPct, cs)))),
            fixedWidth: 112,
            tooltip: 'All-in return on principal: (Total Value − Initial) / Initial'),
        // Projected payoff %, highlighted by status: red loss / amber when the
        // cap is reached. A single amber lock (with a tooltip) flags ONLY a
        // capped-out product — below-cap and uncapped show no icon, so the lock
        // unambiguously means "maxed out".
        _Col('Unrealized %', true, (h, _) => h.projGain, (h, _, cs) {
          final st = h.gainStatus;
          final color = gainStatusColor(st, cs);
          final capped = st == GainStatus.capped;
          final icon = capped ? Icons.lock : null;
          final tip = capped ? '${capLabel(h.cap)} cap reached' : null;
          // Text.rich (not a Row) so it clips rather than overflowing the
          // fixed-width column.
          final text = Text.rich(
            TextSpan(children: [
              TextSpan(text: pctSigned(h.projGain)),
              if (icon != null)
                WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Padding(
                        padding: const EdgeInsets.only(left: 3),
                        child: Icon(icon, size: 12, color: color))),
            ]),
            style: TextStyle(color: color),
            overflow: TextOverflow.clip,
          );
          return DataCell(tip != null ? Tooltip(message: tip, child: text) : text);
        }, fixedWidth: 112), // match "Unrealized $" so the headers wrap alike
        _Col('Index Gain', true, (h, _) => h.indexGain, (h, _, cs) => _signed(h.indexGain, cs),
            fixedWidth: 92),
        // Life-to-date yield: annualized (CAGR) return since the open date using
        // the current projected value; cumulative (un-annualized) under 1 year.
        _Col('Yield', true, (h, a) => h.lifeToDateYield(a), (h, a, cs) => DataCell(
            Text(h.initial <= 0 ? '' : pctSigned(h.lifeToDateYield(a)),
                style: TextStyle(color: lossColor(h.lifeToDateYield(a), cs)))),
            fixedWidth: 92,
            tooltip: 'Annualized return since inception (life-to-date, current '
                'value); under 1 year shows cumulative return'),
        // Timing (monitor)
        _Col('Next Reset', false, (h, _) => h.nextReset, (h, _, _) => _t(date(h.nextReset)),
            fixedWidth: 92),
        _Col('Days to Reset', true, (h, a) => h.daysToReset(a), (h, a, _) => _t('${h.daysToReset(a)}'),
            fixedWidth: 84),
        _Col('Maturity', false, (h, _) => h.maturity, (h, _, _) => _t(date(h.maturity)),
            fixedWidth: 92),
        _Col('Days to Maturity', true, (h, a) => h.daysToMaturity(a), (h, a, _) => _t('${h.daysToMaturity(a)}'),
            fixedWidth: 96),
        // Terms (static)
        _Col('CAP', true, (h, _) => h.cap ?? double.infinity, (h, _, _) => _t(capLabel(h.cap)),
            fixedWidth: 88), // fits "Uncapped" on one line
        _Col('Part.', true, (h, _) => h.participation, (h, _, _) => _t(pct(h.participation)),
            fixedWidth: 80),
        _Col('Floor', true, (h, _) => h.floor, (h, _, _) => _t(h.floor == 0 ? '0.00%' : pct(h.floor)),
            fixedWidth: 84),
        _Col('Strike', true, (h, _) => h.strike, (h, _, _) => _t(level(h.strike)),
            fixedWidth: 92),
        _Col('Reset Freq', false, (h, _) => h.resetFreq.index, (h, _, _) => _t(h.resetFreq.label),
            fixedWidth: 100),
        _Col('Start Date', false, (h, _) => h.openDate, (h, _, _) => _t(date(h.openDate)),
            fixedWidth: 92),
        _Col('Last Reset', false, (h, _) => h.lastReset, (h, _, _) => _t(date(h.lastReset)),
            fixedWidth: 92),
        // Original investment date for rolled contracts; drives Yield/XIRR's
        // start. Blank when not set (Yield then measures from Open).
        _Col('Inception', false, (h, _) => h.inceptionDate ?? DateTime(9999),
            (h, _, _) => _t(h.inceptionDate == null ? '' : date(h.inceptionDate!)),
            fixedWidth: 92,
            tooltip: 'Original investment date (for rolled contracts). When set, '
                'Yield/CAGR and XIRR measure from here instead of Open.'),
      ];

  /// Columns shown in the compact "core" view (identity + key inputs/outcome
  /// + the monitored reset countdown). Full view shows everything.
  static const _coreLabels = <String>{
    'Issuer', 'Type', 'Index', 'Protection',
    'Initial', 'Realized', 'Unrealized \$', 'Total Value', 'Return %',
    'Unrealized %', 'Index Gain', 'Yield', 'Next Reset', 'Days to Reset',
  };

  /// The leading identity columns, frozen when scrolling horizontally.
  static const _identityLabels = <String>{'Issuer', 'Type', 'Index', 'Protection'};

  @override
  Widget build(BuildContext context) {
    final store = context.watch<PortfolioStore>();
    final asOf = store.market?.asOf ?? DateTime(2026, 6, 14);
    final cs = Theme.of(context).colorScheme;
    final all = _columns(cs);
    final shown =
        store.fullColumns ? all : all.where((c) => _coreLabels.contains(c.label)).toList();

    // Sort uses the FULL-list column identity so it survives view switches.
    final sortIdxAll = store.sortColumn.clamp(0, all.length - 1);
    final items = orderedHoldings(store, asOf, cs);
    // Position of the sorted column within the shown list (null if hidden).
    final shownSortIdx = shown.indexOf(all[sortIdxAll]);

    return LayoutBuilder(builder: (context, constraints) {
      // Narrow viewports (phones) get a card list instead of the wide table.
      if (constraints.maxWidth < 720) {
        return _cardList(context, store, items, asOf, cs);
      }
      // Freeze the leading identity columns (and the header row) so they stay
      // put while scrolling a large portfolio. Every column is fixedWidth, so it
      // packs tight (no per-column gaps / lopsided distribution in compact view);
      // any leftover viewport width is a single trailing margin, and the table
      // scrolls when narrower than the total.
      final frozen = shown.takeWhile((c) => _identityLabels.contains(c.label)).length;
      final minW = shown.fold<double>(
          104 + 28 /*actions + margins*/, (s, c) => s + (c.fixedWidth ?? 124));

      return DataTable2(
        columnSpacing: 16,
        horizontalMargin: 12,
        minWidth: minW,
        fixedTopRows: 1,
        fixedLeftColumns: frozen,
        showCheckboxColumn: false,
        sortColumnIndex: shownSortIdx >= 0 ? shownSortIdx : null,
        sortAscending: store.sortAscending,
        headingRowColor: WidgetStatePropertyAll(cs.primary),
        headingTextStyle: TextStyle(
            color: cs.onPrimary, fontWeight: FontWeight.w600, fontSize: 12.5),
        headingRowHeight: 52,
        dataRowHeight: 44,
        columns: [
          for (final c in shown)
            DataColumn2(
              // Wrapped headers align with their data: numeric right, text left.
              label: Text(c.label,
                  softWrap: true,
                  textAlign: c.numeric ? TextAlign.right : TextAlign.left),
              numeric: c.numeric,
              tooltip: c.tooltip,
              size: _colSize(c),
              fixedWidth: c.fixedWidth,
              onSort: (i, asc) => store.setSort(all.indexOf(shown[i]), asc),
            ),
          const DataColumn2(label: Text('Actions'), size: ColumnSize.S, fixedWidth: 104),
          // Flexible blank spacer: absorbs any leftover viewport width as a
          // single trailing margin so every data column stays tight (instead of
          // the slack spreading into per-column gaps).
          const DataColumn2(label: Text(''), size: ColumnSize.L),
        ],
        rows: [
          ..._bodyRows(context, store, shown, items, asOf, cs),
          _totalsRow(shown, store, cs),
        ],
      );
    });
  }

  /// The table body: a flat list of data rows, or — when a group-by dimension is
  /// active — a header + member rows + subtotal for each group.
  List<DataRow> _bodyRows(BuildContext context, PortfolioStore store,
      List<_Col> shown, List<Holding> items, DateTime asOf, ColorScheme cs) {
    if (store.groupBy.isEmpty) {
      return [
        for (final (i, x) in items.indexed)
          _dataRow(context, store, shown, x, asOf, cs, i),
      ];
    }
    final rows = <DataRow>[];
    var i = 0; // running index for zebra striping across all groups
    _grouped(items, store.groupBy).forEach((value, members) {
      final collapsed = store.isGroupCollapsed(value);
      // The group header carries the subtotals (name + count + summed money),
      // plus the group's money-weighted XIRR. A chevron toggles collapse.
      rows.add(_totalsBandRow(shown, members, cs,
          label: '$value  (${members.length})',
          bg: cs.primaryContainer,
          labelColor: cs.onPrimaryContainer,
          yieldXirr: store.xirrFor(members),
          chevron: collapsed ? Icons.chevron_right : Icons.expand_more,
          onToggle: () => store.toggleGroupCollapsed(value)));
      if (!collapsed) {
        for (final x in members) {
          rows.add(_dataRow(context, store, shown, x, asOf, cs, i++));
        }
      }
    });
    return rows;
  }

  DataRow _dataRow(BuildContext context, PortfolioStore store, List<_Col> shown,
      Holding x, DateTime asOf, ColorScheme cs, int i) {
    return DataRow2(
      color: WidgetStateProperty.resolveWith(
          (_) => i.isOdd ? cs.onSurface.withValues(alpha: 0.035) : null),
      onTap: () => Navigator.of(context).push(detailRoute(x)),
      cells: [
        for (final c in shown) c.cell(x, asOf, cs),
        DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit, size: 18),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            onPressed: () => _edit(context, store, x),
          ),
        ])),
        const DataCell(SizedBox.shrink()), // spacer
      ],
    );
  }

  /// Relative column width (flexible, so columns fill the viewport width).
  // Only the flexible (non-fixedWidth) columns consult this — names/money/dates.
  // Issuer gets the most slack; the rest share evenly.
  static ColumnSize _colSize(_Col c) => switch (c.label) {
        'Issuer' => ColumnSize.L,
        _ => ColumnSize.M,
      };

  /// Holdings in the table's current sort order — shared with the report export
  /// so it mirrors the on-screen sort. (cs only builds the column list; the sort
  /// keys don't depend on it.)
  static List<Holding> orderedHoldings(
      PortfolioStore store, DateTime asOf, ColorScheme cs) {
    final all = _columns(cs);
    final keyer = all[store.sortColumn.clamp(0, all.length - 1)].key;
    final items = [...store.holdings];
    items.sort((a, b) {
      final r = keyer(a, asOf).compareTo(keyer(b, asOf));
      return store.sortAscending ? r : -r;
    });
    return items;
  }

  /// Column labels in table order (sort indices index into this list).
  static List<String> columnLabels(ColorScheme cs) =>
      _columns(cs).map((c) => c.label).toList();

  /// Sort-column index for a group dimension — the dimension labels match their
  /// column labels 1:1 (Issuer/Type/Index/Protection/Reset Freq), so grouping
  /// can sort the table by the grouped column. Returns -1 if there's no match.
  static int columnIndexForDimension(String dim, ColorScheme cs) =>
      columnLabels(cs).indexOf(dim);

  /// The value a holding falls under for the active group-by dimension.
  static String groupValueOf(Holding h, String dim) => switch (dim) {
        'Issuer' => h.issuer,
        'Type' => h.account.label,
        'Index' => indexLabel(h.index),
        'Protection' => h.protectionType,
        'Reset Freq' => h.resetFreq.label,
        _ => '',
      };

  /// Split [items] into groups in first-appearance order (so within-group order
  /// stays the current sort), keyed by [dim]'s value.
  static Map<String, List<Holding>> _grouped(List<Holding> items, String dim) {
    final map = <String, List<Holding>>{};
    for (final h in items) {
      (map[groupValueOf(h, dim)] ??= []).add(h);
    }
    return map;
  }

  /// Bold portfolio TOTAL row under the money columns.
  DataRow _totalsRow(List<_Col> shown, PortfolioStore store, ColorScheme cs) =>
      _totalsBandRow(shown, store.holdings, cs,
          label: 'TOTAL',
          bg: cs.surfaceContainerHigh,
          yieldXirr: store.portfolioXirr);

  /// A totals band over an arbitrary holding list: either a group header (the
  /// dimension value + count in the leading cell, subtotals in the money cells)
  /// or the grand-total row. [bg]/[labelColor] style it.
  DataRow _totalsBandRow(List<_Col> shown, List<Holding> items, ColorScheme cs,
      {required String label,
      required Color bg,
      Color? labelColor,
      double? yieldXirr,
      IconData? chevron,
      VoidCallback? onToggle}) {
    final agg = BandAggregates.of(items);
    return DataRow(
      color: WidgetStatePropertyAll(bg),
      // A collapsible group header taps to fold/unfold; the grand total doesn't.
      onSelectChanged: onToggle == null ? null : (_) => onToggle(),
      cells: [
        for (final c in shown)
          if (c.label == 'Issuer' && chevron != null)
            DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(chevron, size: 18, color: labelColor),
              const SizedBox(width: 4),
              Flexible(
                  child: Text(label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontWeight: FontWeight.bold, color: labelColor))),
            ]))
          else
            _totalCell(c.label, cs,
                label: label,
                labelColor: labelColor,
                initial: agg.initial,
                realized: agg.realized,
                projValue: agg.projValue,
                projGain: agg.unrealizedDollars,
                returnPct: agg.returnPct,
                unrealizedPct: agg.unrealizedPct,
                indexGainW: agg.indexGain,
                yieldXirr: yieldXirr),
        const DataCell(Text('')), // Actions
        const DataCell(SizedBox.shrink()), // spacer
      ],
    );
  }

  static DataCell _totalCell(String colLabel, ColorScheme cs,
      {required String label,
      Color? labelColor,
      required double initial,
      required double realized,
      required double projValue,
      required double projGain,
      double? returnPct,
      double? unrealizedPct,
      double? indexGainW,
      double? yieldXirr}) {
    String t = '';
    Color? color = labelColor;
    switch (colLabel) {
      case 'Issuer':
        t = label;
      case 'Initial':
        t = moneyK(initial);
      case 'Realized':
        t = moneyK(realized);
      case 'Total Value':
        t = moneyK(projValue);
      case 'Unrealized \$':
        t = moneyK(projGain);
        color = gainColor(projGain, cs);
      // Weighted ratio aggregates (blank when undefined); losses flagged red.
      case 'Return %':
        if (returnPct != null) {
          t = pctSigned(returnPct);
          color = lossColor(returnPct, cs);
        }
      case 'Unrealized %':
        if (unrealizedPct != null) {
          t = pctSigned(unrealizedPct);
          color = lossColor(unrealizedPct, cs);
        }
      case 'Index Gain':
        if (indexGainW != null) {
          t = pctSigned(indexGainW);
          color = lossColor(indexGainW, cs);
        }
      // Money-weighted annualized return (XIRR) — ties the TOTAL row to the hero.
      case 'Yield':
        if (yieldXirr != null) {
          t = pctSigned(yieldXirr);
          color = lossColor(yieldXirr, cs);
        }
    }
    return DataCell(
        Text(t, style: TextStyle(fontWeight: FontWeight.bold, color: color)));
  }

  /// Phone layout: one card per holding instead of the wide table.
  Widget _cardList(BuildContext context, PortfolioStore store,
      List<Holding> items, DateTime asOf, ColorScheme cs) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 80),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final x = items[i];
        final prot = protectionPalette(x.protectionType, cs);
        final gc = lossColor(x.projGainDollarsK, cs); // red loss, neutral else
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
          child: InkWell(
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => HoldingDetail(holding: x))),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                      child: Text(store.labelFor(x),
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: cs.primary,
                              decoration: TextDecoration.underline,
                              decorationColor: cs.primary))),
                  _pill(x.account.label, cs.secondaryContainer, cs.onSecondaryContainer),
                  const SizedBox(width: 6),
                  _pill(x.protectionType, prot.bg, prot.fg),
                ]),
                const SizedBox(height: 8),
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(moneyK(x.projValueK),
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      Text('Projected Value',
                          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                    ]),
                  ),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('${x.projGainDollarsK >= 0 ? '▲' : '▼'} ${moneyK(x.projGainDollarsK)}',
                        style: TextStyle(color: gc, fontWeight: FontWeight.w600)),
                    Text(pctSigned(x.projGain),
                        style: TextStyle(
                            fontSize: 12, color: gainStatusColor(x.gainStatus, cs))),
                  ]),
                ]),
                const Divider(height: 18),
                Row(children: [
                  _meta('Index', x.index, cs),
                  _meta('Index Gain', pctSigned(x.indexGain), cs),
                  _meta('Next Reset', '${x.daysToReset(asOf)}d · ${date(x.nextReset)}', cs),
                ]),
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                      tooltip: 'Edit',
                      icon: const Icon(Icons.edit, size: 18),
                      onPressed: () => _edit(context, store, x)),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }

  static Widget _meta(String label, String value, ColorScheme cs) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
          Text(value, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
        ]),
      );

  Future<void> _edit(BuildContext context, PortfolioStore store, Holding x) async {
    // Delete now lives inside the edit panel (it isn't a routine, per-row action).
    // The form pops itself when a delete goes through, so `edited` is null then.
    final edited = await Navigator.of(context).push<Holding>(MaterialPageRoute(
        builder: (_) =>
            HoldingForm(initial: x, onDelete: () => _delete(context, store, x))));
    if (edited != null) await store.upsert(edited, replacing: x);
  }

  /// Confirm + delete [x]; returns true when it was actually removed (so the
  /// edit panel knows to close). Keeps the typed-phrase guard, backup offer, and
  /// encryption re-auth.
  Future<bool> _delete(BuildContext context, PortfolioStore store, Holding x) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await confirmTyped(
      context,
      title: 'Delete holding?',
      message: '⚠️ This permanently removes ${store.labelFor(x)} from your '
          'locally stored portfolio and cannot be undone. Export a backup first '
          'if you want to keep a copy.',
      phrase: 'delete',
      confirmLabel: 'Delete',
      destructive: true,
      verifyPassphrase: store.encryptionEnabled ? store.verifyPassphrase : null,
      verifyBiometric: store.biometricEnabled ? store.verifyBiometric : null,
      verifyRecoveryCode:
          store.encryptionEnabled ? store.verifyRecoveryCode : null,
      onBackup: () async {
        await exportBackup(store);
        messenger.showSnackBar(const SnackBar(content: Text('Backup exported')));
      },
    );
    if (ok) await store.remove(x);
    return ok;
  }
}
