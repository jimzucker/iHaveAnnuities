// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: Apache-2.0
// Shared destructive-action guards: a typed-confirmation dialog (the user must
// type a phrase before the action enables) plus a one-call .xlsx backup export.
// Used by both "Clear all data" and "Delete holding" so they guard alike.

import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';

import '../data/portfolio_store.dart';
import 'format.dart';

/// Export the whole portfolio as a dated `.xlsx` backup download.
Future<void> exportBackup(PortfolioStore store) => FileSaver.instance.saveFile(
      name: exportFileName(),
      bytes: Uint8List.fromList(store.exportXlsx()),
      fileExtension: 'xlsx',
      mimeType: MimeType.microsoftExcel,
    );

/// Show a typed-confirmation dialog. Returns true only if the user typed
/// [phrase] and confirmed. [onBackup] adds an "Export backup" button.
/// [verifyPassphrase], when provided, additionally requires the correct vault
/// passphrase before the action proceeds (destructive actions when encrypted).
Future<bool> confirmTyped(
  BuildContext context, {
  required String title,
  required String message,
  required String phrase,
  required String confirmLabel,
  bool destructive = false,
  Future<void> Function()? onBackup,
  Future<bool> Function(String)? verifyPassphrase,
  Future<bool> Function()? verifyBiometric,
  Future<bool> Function(String)? verifyRecoveryCode,
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
      verifyPassphrase: verifyPassphrase,
      verifyBiometric: verifyBiometric,
      verifyRecoveryCode: verifyRecoveryCode,
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
    this.verifyPassphrase,
    this.verifyBiometric,
    this.verifyRecoveryCode,
  });
  final String title;
  final String message;
  final String phrase;
  final String confirmLabel;
  final bool destructive;
  final Future<void> Function()? onBackup;
  final Future<bool> Function(String)? verifyPassphrase;
  final Future<bool> Function()? verifyBiometric;
  final Future<bool> Function(String)? verifyRecoveryCode;

  @override
  State<TypedConfirmDialog> createState() => _TypedConfirmDialogState();
}

class _TypedConfirmDialogState extends State<TypedConfirmDialog> {
  final _controller = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  bool _useRecovery = false; // verify with the recovery code instead
  String? _passError;

  @override
  void dispose() {
    _controller.dispose();
    _pass.dispose();
    super.dispose();
  }

  bool get _matches =>
      _controller.text.trim().toLowerCase() == widget.phrase.toLowerCase();

  Future<void> _submit() async {
    if (!_matches || _busy) return;
    final verify =
        _useRecovery ? widget.verifyRecoveryCode : widget.verifyPassphrase;
    if (verify == null) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      _busy = true;
      _passError = null;
    });
    final ok = await verify(_pass.text);
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _busy = false;
        _passError =
            _useRecovery ? 'Invalid recovery code' : 'Incorrect passphrase';
      });
    }
  }

  Future<void> _submitBiometric() async {
    if (!_matches || _busy) return;
    setState(() {
      _busy = true;
      _passError = null;
    });
    final ok = await widget.verifyBiometric!();
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _busy = false;
        _passError = 'Touch ID failed';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final needsPass = widget.verifyPassphrase != null;
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
            enabled: !_busy,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => needsPass ? null : _submit(),
            decoration: InputDecoration(
              labelText: 'Type "${widget.phrase}" to confirm',
              border: const OutlineInputBorder(),
            ),
          ),
          if (needsPass) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _pass,
              obscureText: !_useRecovery,
              enabled: !_busy,
              textCapitalization: _useRecovery
                  ? TextCapitalization.characters
                  : TextCapitalization.none,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: _useRecovery
                    ? 'Recovery code'
                    : 'Confirm with your passphrase',
                border: const OutlineInputBorder(),
                errorText: _passError,
              ),
            ),
            if (widget.verifyRecoveryCode != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                            _useRecovery = !_useRecovery;
                            _passError = null;
                            _pass.clear();
                          }),
                  child: Text(_useRecovery
                      ? 'Use passphrase'
                      : 'Forgot? Use recovery code'),
                ),
              ),
          ],
        ],
      ),
      actions: [
        if (widget.onBackup != null)
          TextButton.icon(
            onPressed: _busy ? null : () => widget.onBackup!(),
            icon: const Icon(Icons.download, size: 18),
            label: const Text('Export backup'),
          ),
        if (widget.verifyBiometric != null)
          TextButton.icon(
            onPressed: (_matches && !_busy) ? _submitBiometric : null,
            icon: const Icon(Icons.fingerprint, size: 18),
            label: const Text('Touch ID'),
          ),
        TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context, false),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: (_matches && !_busy) ? _submit : null,
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
