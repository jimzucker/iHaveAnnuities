// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: Apache-2.0

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../data/portfolio_store.dart';
import 'format.dart';
import 'holding_form.dart';
import 'index_chart_screen.dart';
import 'info_page.dart';
import 'portfolio_hero.dart';
import 'portfolio_table.dart';

class PortfolioScreen extends StatelessWidget {
  const PortfolioScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<PortfolioStore>();
    // The table (and its compact-columns toggle) only show on wide viewports;
    // phones use the card layout where the toggle has no effect.
    final wide = MediaQuery.of(context).size.width >= 720;
    return Scaffold(
      appBar: AppBar(
        leading: const Padding(
          padding: EdgeInsets.only(left: 12),
          child: Icon(Icons.trending_up),
        ),
        title: const Text('iHaveAnnuities'),
        actions: [
          IconButton(
            tooltip: 'Refresh prices',
            icon: store.refreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
            onPressed: store.refreshing ? null : () => _refresh(context, store),
          ),
          if (!store.isEmpty && wide)
            IconButton(
              tooltip: store.fullColumns ? 'Compact columns' : 'All columns',
              icon: Icon(store.fullColumns
                  ? Icons.view_column
                  : Icons.view_column_outlined),
              onPressed: () => store.setFullColumns(!store.fullColumns),
            ),
          PopupMenuButton<String>(
            onSelected: (v) => _menu(context, store, v),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'import', child: Text('Import .xlsx…')),
              const PopupMenuItem(value: 'export', child: Text('Export .xlsx')),
              const PopupMenuItem(value: 'template', child: Text('Download template')),
              PopupMenuItem(
                value: 'sample',
                // Only as a starter — clear the portfolio first to re-enable.
                enabled: store.isEmpty,
                child: const Text('Load sample'),
              ),
              const PopupMenuItem(value: 'clear', child: Text('Clear all data')),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'about', child: Text('About & disclosures')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context, store),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: Column(
        children: [
          if (!store.isEmpty)
            _SummaryToggle(
              hidden: store.hideSummary,
              onTap: () => store.setHideSummary(!store.hideSummary),
            ),
          if (!store.hideSummary) const _PricesHeader(),
          if (store.status != null)
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.errorContainer,
              padding: const EdgeInsets.all(8),
              child: Text(store.status!,
                  style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)),
            ),
          if (!store.isEmpty && !store.hideSummary) const PortfolioHero(),
          Expanded(
            child: store.isEmpty
                ? _Empty(
                    onAdd: () => _add(context, store),
                    onImport: () => _menu(context, store, 'import'),
                    onTemplate: () => _menu(context, store, 'template'),
                    onSample: () => _menu(context, store, 'sample'),
                    onAbout: () => _menu(context, store, 'about'),
                  )
                : const Padding(
                    padding: EdgeInsets.all(8),
                    child: PortfolioTable(),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _refresh(BuildContext context, PortfolioStore store) async {
    final messenger = ScaffoldMessenger.of(context);
    await store.refreshMarket();
    messenger.showSnackBar(SnackBar(
      content: Text(store.status ?? 'Prices updated ${date(store.market!.asOf)}'),
    ));
  }

  Future<void> _add(BuildContext context, PortfolioStore store) async {
    final h = await Navigator.of(context)
        .push<Holding>(MaterialPageRoute(builder: (_) => const HoldingForm()));
    if (h != null) await store.upsert(h);
  }

  Future<void> _menu(BuildContext context, PortfolioStore store, String v) async {
    final messenger = ScaffoldMessenger.of(context);
    switch (v) {
      case 'import':
        // Importing replaces the current holdings — guard it when there's data.
        if (!store.isEmpty &&
            !await _confirmTyped(context,
                title: 'Replace portfolio?',
                message: 'Importing a spreadsheet replaces all your current '
                    'holdings. This can\'t be undone.',
                phrase: 'load',
                confirmLabel: 'Load')) {
          return;
        }
        final res = await FilePicker.pickFiles(
            type: FileType.custom, allowedExtensions: ['xlsx'], withData: true);
        final bytes = res?.files.single.bytes;
        if (bytes != null) {
          try {
            final n = await store.importXlsx(bytes);
            messenger.showSnackBar(SnackBar(content: Text('Imported $n holdings')));
          } catch (e) {
            messenger.showSnackBar(SnackBar(content: Text('Import failed: $e')));
          }
        }
      case 'export':
        await _save('iHaveAnnuities.xlsx', Uint8List.fromList(store.exportXlsx()));
        messenger.showSnackBar(const SnackBar(content: Text('Exported .xlsx')));
      case 'template':
        final data = await rootBundle.load('assets/template.xlsx');
        await _save('iHaveAnnuities-template.xlsx', data.buffer.asUint8List());
        messenger.showSnackBar(const SnackBar(content: Text('Template downloaded')));
      case 'sample':
        if (!store.isEmpty) {
          messenger.showSnackBar(const SnackBar(
              content: Text('Clear all data before loading the sample.')));
          return;
        }
        final data = await rootBundle.load('assets/example-portfolio.xlsx');
        final n = await store.importXlsx(data.buffer.asUint8List());
        messenger.showSnackBar(SnackBar(content: Text('Loaded $n sample holdings')));
      case 'clear':
        if (!await _confirmTyped(context,
            title: 'Clear all data?',
            message: '⚠️ This permanently deletes your locally stored portfolio '
                'and cannot be undone. Export a backup first if you want to keep '
                'a copy.',
            phrase: 'clear all data',
            confirmLabel: 'Clear all data',
            destructive: true,
            onBackup: () async {
              await _save(
                  'iHaveAnnuities-backup.xlsx', Uint8List.fromList(store.exportXlsx()));
              messenger.showSnackBar(
                  const SnackBar(content: Text('Backup exported')));
            })) {
          return;
        }
        await store.clearLocal();
        messenger.showSnackBar(const SnackBar(content: Text('All data cleared')));
      case 'about':
        await Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const InfoPage()));
    }
  }

  /// A confirmation dialog that requires typing [phrase] before the action
  /// button enables — a precaution for destructive / overwriting actions.
  Future<bool> _confirmTyped(
    BuildContext context, {
    required String title,
    required String message,
    required String phrase,
    required String confirmLabel,
    bool destructive = false,
    Future<void> Function()? onBackup,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _TypedConfirmDialog(
        title: title,
        message: message,
        phrase: phrase,
        confirmLabel: confirmLabel,
        destructive: destructive,
        onBackup: onBackup,
      ),
    );
    return ok ?? false;
  }

  Future<void> _save(String name, Uint8List bytes) => FileSaver.instance.saveFile(
        name: name.replaceAll('.xlsx', ''),
        bytes: bytes,
        fileExtension: 'xlsx',
        mimeType: MimeType.microsoftExcel,
      );
}

class _PricesHeader extends StatelessWidget {
  const _PricesHeader();
  @override
  Widget build(BuildContext context) {
    final store = context.watch<PortfolioStore>();
    final m = store.market;
    final cs = Theme.of(context).colorScheme;
    // Large-cap benchmarks first, the two Nasdaqs adjacent, then small-caps.
    final quotes = m == null
        ? const <(String, String, double?)>[]
        : <(String, String, double?)>[
            ('S&P 500', 'SPX', m.spx),
            ('Dow', 'DJI', m.dow),
            ('Nasdaq Comp', 'COMP', m.comp),
            ('Nasdaq-100', 'NDX', m.ndx),
            ('Russell 2000', 'RUT', m.rut),
          ];
    return Container(
      width: double.infinity,
      color: cs.primaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: DefaultTextStyle(
        style: TextStyle(color: cs.onPrimaryContainer, fontSize: 13),
        child: m == null
            ? const Text('Loading prices…')
            : Wrap(spacing: 18, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                for (final q in quotes)
                  if (q.$3 != null)
                    InkWell(
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => IndexChartScreen(base: store.base))),
                      child: _Quote(q.$1, q.$3!),
                    ),
                Icon(Icons.show_chart, size: 15, color: cs.onPrimaryContainer),
                Text('updated ${date(m.asOf)}',
                    style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 12)),
              ]),
      ),
    );
  }
}

class _Quote extends StatelessWidget {
  const _Quote(this.label, this.value);
  final String label;
  final double value;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Underlined to read as a link (tap → combined index chart).
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: '$label '),
        TextSpan(text: level(value), style: const TextStyle(fontWeight: FontWeight.bold)),
      ]),
      style: TextStyle(
        decoration: TextDecoration.underline,
        decorationColor: cs.onPrimaryContainer.withValues(alpha: 0.6),
      ),
    );
  }
}

/// A thin, labeled, tappable strip that collapses/expands the prices + hero.
class _SummaryToggle extends StatelessWidget {
  const _SummaryToggle({required this.hidden, required this.onTap});
  final bool hidden;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        color: cs.surfaceContainerHighest,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(children: [
          Icon(hidden ? Icons.expand_more : Icons.expand_less,
              size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(hidden ? 'Show summary' : 'Hide summary',
              style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

/// Dialog requiring the user to type a phrase before the action enables.
class _TypedConfirmDialog extends StatefulWidget {
  const _TypedConfirmDialog({
    required this.title,
    required this.message,
    required this.phrase,
    required this.confirmLabel,
    this.destructive = false,
    this.onBackup,
  });
  final String title;
  final String message;
  final String phrase;
  final String confirmLabel;
  final bool destructive;
  final Future<void> Function()? onBackup;

  @override
  State<_TypedConfirmDialog> createState() => _TypedConfirmDialogState();
}

class _TypedConfirmDialogState extends State<_TypedConfirmDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final matches =
        _controller.text.trim().toLowerCase() == widget.phrase.toLowerCase();
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.message),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) {
              if (matches) Navigator.pop(context, true);
            },
            decoration: InputDecoration(
              labelText: 'Type "${widget.phrase}" to confirm',
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        if (widget.onBackup != null)
          TextButton.icon(
            onPressed: () => widget.onBackup!(),
            icon: const Icon(Icons.download, size: 18),
            label: const Text('Export backup'),
          ),
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: matches ? () => Navigator.pop(context, true) : null,
          style: widget.destructive
              ? FilledButton.styleFrom(
                  backgroundColor: cs.error, foregroundColor: cs.onError)
              : null,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({
    required this.onAdd,
    required this.onImport,
    required this.onTemplate,
    required this.onSample,
    required this.onAbout,
  });
  final VoidCallback onAdd;
  final VoidCallback onImport;
  final VoidCallback onTemplate;
  final VoidCallback onSample;
  final VoidCallback onAbout;

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('No holdings yet',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('Add a contract, import your tracker, or load the sample.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add),
                label: const Text('Add a holding manually')),
            const SizedBox(height: 8),
            OutlinedButton.icon(
                onPressed: onImport,
                icon: const Icon(Icons.upload_file),
                label: const Text('Import .xlsx…')),
            const SizedBox(height: 8),
            OutlinedButton.icon(
                onPressed: onTemplate,
                icon: const Icon(Icons.download),
                label: const Text('Download template')),
            const SizedBox(height: 8),
            OutlinedButton.icon(
                onPressed: onSample,
                icon: const Icon(Icons.dataset),
                label: const Text('Load sample portfolio')),
            const SizedBox(height: 16),
            TextButton.icon(
                onPressed: onAbout,
                icon: const Icon(Icons.info_outline, size: 18),
                label: const Text('About & disclosures')),
          ]),
        ),
      );
}
