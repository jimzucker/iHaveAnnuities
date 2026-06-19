// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: Apache-2.0
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

/// One sortable column: how to render it and how to sort by it.
class _Col {
  const _Col(this.label, this.numeric, this.key, this.cell, {this.fixedWidth});
  final String label;
  final bool numeric;
  final Comparable Function(Holding h, DateTime asOf) key;
  final DataCell Function(Holding h, DateTime asOf, ColorScheme cs) cell;

  /// When set, the column is exactly this wide (won't flex). Used to keep
  /// short numeric/code columns tight so the slack goes to names/dates/money.
  final double? fixedWidth;
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
        // (Initial + Realized + Unrealized $ = Projected Value), then the two
        // percentages (Unrealized %, Index Gain) sit together for comparison.
        _Col('Unrealized \$', true, (h, _) => h.projGainDollarsK,
            (h, _, cs) => DataCell(Text(moneyK(h.projGainDollarsK),
                style: TextStyle(color: lossColor(h.projGainDollarsK, cs)))),
            fixedWidth: 112),
        _Col('Projected Value', true, (h, _) => h.projValueK, (h, _, _) => _t(moneyK(h.projValueK)),
            fixedWidth: 120),
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
        }, fixedWidth: 104),
        _Col('Index Gain', true, (h, _) => h.indexGain, (h, _, cs) => _signed(h.indexGain, cs),
            fixedWidth: 92),
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
        _Col('Open', false, (h, _) => h.openDate, (h, _, _) => _t(date(h.openDate)),
            fixedWidth: 92),
        _Col('Last Reset', false, (h, _) => h.lastReset, (h, _, _) => _t(date(h.lastReset)),
            fixedWidth: 92),
      ];

  /// Columns shown in the compact "core" view (identity + key inputs/outcome
  /// + the monitored reset countdown). Full view shows everything.
  static const _coreLabels = <String>{
    'Issuer', 'Type', 'Index', 'Protection',
    'Initial', 'Realized', 'Projected Value', 'Unrealized \$', 'Unrealized %',
    'Index Gain', 'Next Reset', 'Days to Reset',
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
    final keyer = all[sortIdxAll].key;
    final items = [...store.holdings];
    items.sort((a, b) {
      final r = keyer(a, asOf).compareTo(keyer(b, asOf));
      return store.sortAscending ? r : -r;
    });
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
          for (final (i, x) in items.indexed)
            DataRow2(
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
                  IconButton(
                    tooltip: 'Delete',
                    icon: const Icon(Icons.delete_outline, size: 18),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    onPressed: () => _delete(context, store, x),
                  ),
                ])),
                const DataCell(SizedBox.shrink()), // spacer
              ],
            ),
          _totalsRow(shown, store, cs),
        ],
      );
    });
  }

  /// Relative column width (flexible, so columns fill the viewport width).
  // Only the flexible (non-fixedWidth) columns consult this — names/money/dates.
  // Issuer gets the most slack; the rest share evenly.
  static ColumnSize _colSize(_Col c) => switch (c.label) {
        'Issuer' => ColumnSize.L,
        _ => ColumnSize.M,
      };

  /// Bold portfolio TOTAL row under the money columns.
  DataRow _totalsRow(List<_Col> shown, PortfolioStore store, ColorScheme cs) =>
      DataRow(
        color: WidgetStatePropertyAll(cs.surfaceContainerHigh),
        cells: [
          for (final c in shown) _totalCell(c.label, store, cs),
          const DataCell(Text('')), // Actions
          const DataCell(SizedBox.shrink()), // spacer
        ],
      );

  static DataCell _totalCell(String label, PortfolioStore store, ColorScheme cs) {
    String t = '';
    Color? color;
    switch (label) {
      case 'Issuer':
        t = 'TOTAL';
      case 'Initial':
        t = moneyK(store.totalInitial);
      case 'Realized':
        t = moneyK(store.totalRealized);
      case 'Projected Value':
        t = moneyK(store.totalProjValue);
      case 'Unrealized \$':
        t = moneyK(store.totalProjGain);
        color = gainColor(store.totalProjGain, cs);
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
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                        tooltip: 'Edit',
                        icon: const Icon(Icons.edit, size: 18),
                        onPressed: () => _edit(context, store, x)),
                    IconButton(
                        tooltip: 'Delete',
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: () => _delete(context, store, x)),
                  ]),
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
    final edited = await Navigator.of(context)
        .push<Holding>(MaterialPageRoute(builder: (_) => HoldingForm(initial: x)));
    if (edited != null) await store.upsert(edited, replacing: x);
  }

  Future<void> _delete(BuildContext context, PortfolioStore store, Holding x) async {
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
      onBackup: () async {
        await exportBackup(store);
        messenger.showSnackBar(const SnackBar(content: Text('Backup exported')));
      },
    );
    if (ok) await store.remove(x);
  }
}
