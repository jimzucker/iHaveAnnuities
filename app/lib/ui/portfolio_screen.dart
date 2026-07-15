// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: LicenseRef-Proprietary

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:provider/provider.dart';

import '../core/models.dart';
import '../data/app_reload.dart';
import '../data/portfolio_store.dart';
import 'confirm.dart';
import 'format.dart';
import 'holding_form.dart';
import 'index_chart_screen.dart';
import 'info_page.dart';
import 'guide_screen.dart';
import 'portfolio_hero.dart';
import 'portfolio_table.dart';
import 'reauth.dart';
import 'reset_history_screen.dart';
import 'security_screen.dart';

class PortfolioScreen extends StatelessWidget {
  const PortfolioScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<PortfolioStore>();
    final cs = Theme.of(context).colorScheme;
    // The table and its view controls only show on wide viewports; phones use
    // the card layout where they have no effect.
    final wide = MediaQuery.of(context).size.width >= 720;
    final grouping = store.groupBy.isNotEmpty;
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
          // View controls stay put (fixed widths) and never appear/disappear —
          // the Collapse button greys out when nothing is grouped rather than
          // hiding, so the app bar doesn't shift as state changes.
          if (!store.isEmpty && wide) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: PopupMenuButton<bool>(
                tooltip: 'Show all columns or a compact set',
                onSelected: store.setFullColumns,
                itemBuilder: (_) => [
                  CheckedPopupMenuItem(
                      value: true,
                      checked: store.fullColumns,
                      child: const Text('All columns')),
                  CheckedPopupMenuItem(
                      value: false,
                      checked: !store.fullColumns,
                      child: const Text('Compact')),
                ],
                child: _BarButton(
                  icon: Icons.view_column,
                  width: 168,
                  label:
                      store.fullColumns ? 'Columns: All' : 'Columns: Compact',
                  dropdown: true,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: PopupMenuButton<String>(
                tooltip: 'Group the table by a column',
                onSelected: store.setGroupBy,
                itemBuilder: (_) => [
                  CheckedPopupMenuItem(
                      value: '',
                      checked: store.groupBy.isEmpty,
                      child: const Text('No grouping')),
                  const PopupMenuDivider(),
                  for (final dim in PortfolioStore.groupDimensions)
                    CheckedPopupMenuItem(
                        value: dim,
                        checked: store.groupBy == dim,
                        child: Text(dim)),
                ],
                child: _BarButton(
                  icon: Icons.segment,
                  width: 200,
                  label: grouping ? 'Group: ${store.groupBy}' : 'Group: Off',
                  active: grouping,
                  dropdown: true,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 4, right: 8),
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: cs.onSurface),
                icon: Icon(
                    store.allGroupsCollapsed
                        ? Icons.unfold_more
                        : Icons.unfold_less,
                    size: 18),
                label: Text(
                    store.allGroupsCollapsed ? 'Expand all' : 'Collapse all'),
                // Disabled (greyed) until grouping is on — not hidden — so the
                // bar layout stays fixed.
                onPressed: !grouping
                    ? null
                    : () {
                        if (store.allGroupsCollapsed) {
                          store.expandAllGroups({
                            for (final h in store.holdings)
                              PortfolioTable.groupValueOf(h, store.groupBy)
                          });
                        } else {
                          store.collapseAllGroups();
                        }
                      },
              ),
            ),
          ],
          // Only shown when encrypted — a closed lock that locks the app now.
          // (Encryption setup lives in the overflow "Security" menu.)
          if (store.encryptionEnabled)
            IconButton(
              tooltip: 'Lock now',
              icon: const Icon(Icons.lock),
              onPressed: () => store.lock(),
            ),
          PopupMenuButton<String>(
            onSelected: (v) => _menu(context, store, v),
            // Help first (most-reached, safe) · Data · Security · destructive last.
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'about', child: Text('About & disclosures')),
              const PopupMenuItem(value: 'guide', child: Text('User Guide')),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'import', child: Text('Import .xlsx…')),
              const PopupMenuItem(value: 'export', child: Text('Export .xlsx')),
              const PopupMenuItem(value: 'template', child: Text('Download template')),
              PopupMenuItem(
                value: 'sample',
                // Only as a starter — clear the portfolio first to re-enable.
                enabled: store.isEmpty,
                child: const Text('Load sample'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'security', child: Text('Security')),
              if (store.encryptionEnabled)
                const PopupMenuItem(value: 'lock', child: Text('Lock now')),
              const PopupMenuItem(value: 'resets', child: Text('Reset history')),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'clear', child: Text('Clear all data')),
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
          if (store.newVersionAvailable) const _UpdateBanner(),
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

  /// Open Security, re-authenticating first when encryption is on (so an
  /// unlocked session can't change/disable protection without the passphrase).
  Future<void> _openSecurity(BuildContext context, PortfolioStore store) async {
    if (!await requireReauth(context, store)) return;
    if (!context.mounted) return;
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const SecurityScreen()));
  }

  Future<void> _add(BuildContext context, PortfolioStore store) async {
    final h = await Navigator.of(context)
        .push<Holding>(MaterialPageRoute(builder: (_) => const HoldingForm()));
    if (h != null) {
      await store.upsert(h);
      if (context.mounted) _maybeNudge(context, store);
    }
  }

  /// One-time prompt to consider encryption after data lands on the skip path.
  void _maybeNudge(BuildContext context, PortfolioStore store) {
    if (!store.shouldNudgeEncryption) return;
    store.dismissEncryptionNudge();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 8),
      content: const Text('Your portfolio is stored unencrypted on this device.'),
      action: SnackBarAction(
        label: 'Set up',
        onPressed: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const SecurityScreen())),
      ),
    ));
  }

  Future<void> _menu(BuildContext context, PortfolioStore store, String v) async {
    final messenger = ScaffoldMessenger.of(context);
    switch (v) {
      case 'import':
        // Importing replaces the current holdings — guard it when there's data.
        if (!store.isEmpty &&
            !await confirmTyped(context,
                title: 'Replace portfolio?',
                message: 'Importing a spreadsheet replaces all your current '
                    'holdings. This can\'t be undone.',
                phrase: 'load',
                confirmLabel: 'Load',
                verifyPassphrase:
                    store.encryptionEnabled ? store.verifyPassphrase : null,
                verifyBiometric:
                    store.biometricEnabled ? store.verifyBiometric : null,
                verifyRecoveryCode:
                    store.encryptionEnabled ? store.verifyRecoveryCode : null)) {
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
        // Exporting writes the whole portfolio as plaintext — re-verify identity
        // when encrypted so an unlocked session can't quietly exfiltrate it.
        if (!await requireReauth(context, store)) return;
        await _save('${exportFileName()}.xlsx', Uint8List.fromList(store.exportXlsx()));
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
        if (!await confirmTyped(context,
            title: 'Clear all data?',
            message: '⚠️ This permanently deletes your locally stored portfolio '
                'and cannot be undone. Export a backup first if you want to keep '
                'a copy.',
            phrase: 'clear all data',
            confirmLabel: 'Clear all data',
            destructive: true,
            verifyPassphrase:
                store.encryptionEnabled ? store.verifyPassphrase : null,
            verifyBiometric:
                store.biometricEnabled ? store.verifyBiometric : null,
            verifyRecoveryCode:
                store.encryptionEnabled ? store.verifyRecoveryCode : null,
            onBackup: () async {
              await exportBackup(store);
              messenger.showSnackBar(
                  const SnackBar(content: Text('Backup exported')));
            })) {
          return;
        }
        await store.clearLocal();
        messenger.showSnackBar(const SnackBar(content: Text('All data cleared')));
      case 'guide':
        await Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const GuideScreen()));
      case 'security':
        await _openSecurity(context, store);
      case 'lock':
        await store.lock();
      case 'resets':
        await Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const ResetHistoryScreen()));
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

/// A labeled, bordered control — an icon + text (+ optional dropdown caret) so
/// it reads its purpose and state without relying on a hover tooltip. Highlights
/// (primary tint) when [active]. A fixed [width] keeps neighbours from shifting
/// when the label text changes length.
class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.icon,
    required this.label,
    this.active = false,
    this.dropdown = false,
    this.width,
  });
  final IconData icon;
  final String label;
  final bool active;
  final bool dropdown;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = active ? cs.primary : cs.onSurface;
    final text = Text(label,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 13));
    return Container(
      width: width,
      padding: const EdgeInsets.fromLTRB(10, 7, 6, 7),
      decoration: BoxDecoration(
        color: active ? cs.primary.withValues(alpha: 0.10) : null,
        border: Border.all(color: fg.withValues(alpha: 0.40)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: width == null ? MainAxisSize.min : MainAxisSize.max, children: [
        Icon(icon, size: 16, color: fg),
        const SizedBox(width: 6),
        width == null ? text : Expanded(child: text),
        if (dropdown) Icon(Icons.arrow_drop_down, size: 18, color: fg),
      ]),
    );
  }
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
    // A bordered chip with a chart icon → unmistakably tappable (→ index chart).
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        border: Border.all(color: cs.onPrimaryContainer.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('$label '),
        Text(level(value), style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(width: 5),
        Icon(Icons.show_chart,
            size: 13, color: cs.onPrimaryContainer.withValues(alpha: 0.85)),
      ]),
    );
  }
}

/// A thin, labeled, tappable strip that collapses/expands the prices + hero.
/// Top banner shown when a newer app version has been deployed.
class _UpdateBanner extends StatelessWidget {
  const _UpdateBanner();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final store = context.read<PortfolioStore>();
    return Material(
      color: cs.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(children: [
          Icon(Icons.system_update, size: 18, color: cs.onPrimaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text('A new version of the app is available.',
                style: TextStyle(color: cs.onPrimaryContainer)),
          ),
          TextButton(
            onPressed: store.dismissNewVersion,
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: reloadApp,
            child: const Text('Reload'),
          ),
        ]),
      ),
    );
  }
}

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
