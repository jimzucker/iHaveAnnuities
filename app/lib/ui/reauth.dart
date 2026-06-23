// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: Apache-2.0
// Re-authentication gate for sensitive screens (e.g. Security). Requires the
// vault passphrase, with a recovery-code fallback if forgotten. No-op when
// encryption is off (nothing to protect yet).

import 'package:flutter/material.dart';

import '../data/portfolio_store.dart';

/// Returns true if the user re-authenticates (or encryption is off).
Future<bool> requireReauth(BuildContext context, PortfolioStore store) async {
  if (!store.encryptionEnabled) return true;
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => _ReauthDialog(store: store),
  );
  return ok ?? false;
}

class _ReauthDialog extends StatefulWidget {
  const _ReauthDialog({required this.store});
  final PortfolioStore store;

  @override
  State<_ReauthDialog> createState() => _ReauthDialogState();
}

class _ReauthDialogState extends State<_ReauthDialog> {
  final _input = TextEditingController();
  bool _recovery = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = _recovery
        ? await widget.store.verifyRecoveryCode(_input.text)
        : await widget.store.verifyPassphrase(_input.text);
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _busy = false;
        _error = _recovery ? 'Invalid recovery code' : 'Incorrect passphrase';
      });
    }
  }

  Future<void> _biometric() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await widget.store.verifyBiometric();
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _busy = false;
        _error = 'Touch ID failed';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Confirm it\'s you'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_recovery
              ? 'Enter your recovery code to open Security.'
              : 'Enter your passphrase to open Security.'),
          const SizedBox(height: 12),
          TextField(
            controller: _input,
            obscureText: !_recovery,
            autofocus: true,
            enabled: !_busy,
            textCapitalization:
                _recovery ? TextCapitalization.characters : TextCapitalization.none,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: _recovery ? 'Recovery code' : 'Passphrase',
              border: const OutlineInputBorder(),
              errorText: _error,
            ),
          ),
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                      _recovery = !_recovery;
                      _error = null;
                      _input.clear();
                    }),
            child: Text(_recovery ? 'Use passphrase' : 'Forgot? Use recovery code'),
          ),
        ],
      ),
      actions: [
        if (widget.store.biometricEnabled && !_recovery)
          TextButton.icon(
            onPressed: _busy ? null : _biometric,
            icon: const Icon(Icons.fingerprint, size: 18),
            label: const Text('Touch ID'),
          ),
        TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context, false),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: _busy ? null : _submit, child: const Text('Continue')),
      ],
    );
  }
}
