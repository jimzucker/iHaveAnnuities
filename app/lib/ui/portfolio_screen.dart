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
import 'info_page.dart';
import 'portfolio_table.dart';

class PortfolioScreen extends StatelessWidget {
  const PortfolioScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<PortfolioStore>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('iHaveAnnuities'),
        actions: [
          IconButton(
            tooltip: 'Refresh prices',
            icon: const Icon(Icons.refresh),
            onPressed: store.refreshMarket,
          ),
          PopupMenuButton<String>(
            onSelected: (v) => _menu(context, store, v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'import', child: Text('Import .xlsx…')),
              PopupMenuItem(value: 'export', child: Text('Export .xlsx')),
              PopupMenuItem(value: 'template', child: Text('Download template')),
              PopupMenuItem(value: 'sample', child: Text('Load sample')),
              PopupMenuItem(value: 'clear', child: Text('Clear local data')),
              PopupMenuDivider(),
              PopupMenuItem(value: 'about', child: Text('About & disclosures')),
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
          const _PricesHeader(),
          if (store.status != null)
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.errorContainer,
              padding: const EdgeInsets.all(8),
              child: Text(store.status!,
                  style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)),
            ),
          if (!store.isEmpty) _Summary(store: store),
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

  Future<void> _add(BuildContext context, PortfolioStore store) async {
    final h = await Navigator.of(context)
        .push<Holding>(MaterialPageRoute(builder: (_) => const HoldingForm()));
    if (h != null) await store.upsert(h);
  }

  Future<void> _menu(BuildContext context, PortfolioStore store, String v) async {
    final messenger = ScaffoldMessenger.of(context);
    switch (v) {
      case 'import':
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
        final data = await rootBundle.load('assets/example-portfolio.xlsx');
        final n = await store.importXlsx(data.buffer.asUint8List());
        messenger.showSnackBar(SnackBar(content: Text('Loaded $n sample holdings')));
      case 'clear':
        await store.clearLocal();
        messenger.showSnackBar(const SnackBar(content: Text('Local data cleared')));
      case 'about':
        await Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const InfoPage()));
    }
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
    final m = context.watch<PortfolioStore>().market;
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: cs.primaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: DefaultTextStyle(
        style: TextStyle(color: cs.onPrimaryContainer, fontSize: 13),
        child: m == null
            ? const Text('Loading prices…')
            : Wrap(spacing: 18, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                _Quote('S&P 500', m.spx),
                _Quote('Nasdaq-100', m.ndx),
                _Quote('Russell 2000', m.rut),
                Text('Updated ${date(m.asOf)}',
                    style: const TextStyle(fontStyle: FontStyle.italic)),
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
  Widget build(BuildContext context) => Text.rich(TextSpan(children: [
        TextSpan(text: '$label '),
        TextSpan(text: level(value), style: const TextStyle(fontWeight: FontWeight.bold)),
      ]));
}

class _Summary extends StatelessWidget {
  const _Summary({required this.store});
  final PortfolioStore store;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      color: cs.surfaceContainerHighest,
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
        _stat('Contracts', '${store.holdings.length}', cs.onSurface),
        _stat('Principal', moneyK(store.totalInitial), cs.onSurface),
        _stat('Proj value', moneyK(store.totalProjValue), cs.onSurface),
        _stat('Proj gain', moneyK(store.totalProjGain), gainColor(store.totalProjGain, cs)),
      ]),
    );
  }

  Widget _stat(String k, String v, Color c) => Column(children: [
        Text(k, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Text(v, style: TextStyle(fontWeight: FontWeight.bold, color: c)),
      ]);
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
            const Text('Add a contract, import your tracker, or load the sample.',
                textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
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
