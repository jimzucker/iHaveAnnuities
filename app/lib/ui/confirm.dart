// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: Apache-2.0
// Shared destructive-action guards: a typed-confirmation dialog (the user must
// type a phrase before the action enables) plus a one-call .xlsx backup export.
// Used by both "Clear all data" and "Delete holding" so they guard alike.

import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';

import '../data/portfolio_store.dart';

/// Export the whole portfolio as a timestamp-free `.xlsx` backup download.
Future<void> exportBackup(PortfolioStore store) => FileSaver.instance.saveFile(
      name: 'iHaveAnnuities-backup',
      bytes: Uint8List.fromList(store.exportXlsx()),
      fileExtension: 'xlsx',
      mimeType: MimeType.microsoftExcel,
    );

/// Show a typed-confirmation dialog. Returns true only if the user typed
/// [phrase] and confirmed. [onBackup] adds an "Export backup" button.
Future<bool> confirmTyped(
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
    builder: (_) => TypedConfirmDialog(
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

/// Dialog requiring the user to type [phrase] before the action button enables.
class TypedConfirmDialog extends StatefulWidget {
  const TypedConfirmDialog({
    super.key,
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
  State<TypedConfirmDialog> createState() => _TypedConfirmDialogState();
}

class _TypedConfirmDialogState extends State<TypedConfirmDialog> {
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
