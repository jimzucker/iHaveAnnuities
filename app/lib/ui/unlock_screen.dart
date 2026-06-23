// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: Apache-2.0
// Shown when the vault is locked: passphrase unlock, optional Touch ID, recovery
// with the one-time code, and a last-resort "Forget & reset".

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/portfolio_store.dart';
import 'confirm.dart';

class UnlockScreen extends StatefulWidget {
  const UnlockScreen({super.key});

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  final _pass = TextEditingController();
  final _code = TextEditingController();
  final _newPass = TextEditingController();
  final _newPass2 = TextEditingController();
  bool _recovery = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _pass.dispose();
    _code.dispose();
    _newPass.dispose();
    _newPass2.dispose();
    super.dispose();
  }

  Future<void> _run(Future<bool> Function() action, String failure) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await action();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!ok) _error = failure;
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = context.read<PortfolioStore>();
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                Icon(Icons.lock_outline, size: 48, color: cs.primary),
                const SizedBox(height: 12),
                Text('Portfolio locked',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 24),
                if (!_recovery) ..._passphraseMode(store) else ..._recoveryMode(store),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: cs.error)),
                ],
                const SizedBox(height: 24),
                const Divider(),
                TextButton(
                  onPressed: _busy ? null : () => _forgetReset(store),
                  child: Text('Forget & reset…',
                      style: TextStyle(color: cs.error)),
                ),
              ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _passphraseMode(PortfolioStore store) => [
        TextField(
          controller: _pass,
          obscureText: true,
          autofocus: true,
          enabled: !_busy,
          onSubmitted: (_) => _run(() => store.unlock(_pass.text), 'Incorrect passphrase'),
          decoration: const InputDecoration(
              labelText: 'Passphrase', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _busy ? null : () => _run(() => store.unlock(_pass.text), 'Incorrect passphrase'),
          child: const Text('Unlock'),
        ),
        if (store.biometricEnabled) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy
                ? null
                : () => _run(store.biometricUnlock, 'Touch ID cancelled or failed'),
            icon: const Icon(Icons.fingerprint),
            label: const Text('Unlock with Touch ID'),
          ),
        ],
        const SizedBox(height: 8),
        TextButton(
          onPressed: _busy ? null : () => setState(() { _recovery = true; _error = null; }),
          child: const Text('Use recovery code'),
        ),
      ];

  List<Widget> _recoveryMode(PortfolioStore store) => [
        const Text(
          'Enter your recovery code and choose a new passphrase.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _code,
          autofocus: true,
          enabled: !_busy,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
              labelText: 'Recovery code', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _newPass,
          obscureText: true,
          enabled: !_busy,
          decoration: const InputDecoration(
              labelText: 'New passphrase', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _newPass2,
          obscureText: true,
          enabled: !_busy,
          onSubmitted: (_) => _recover(store),
          decoration: const InputDecoration(
              labelText: 'Confirm new passphrase', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _busy ? null : () => _recover(store),
          child: const Text('Recover & set passphrase'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _busy ? null : () => setState(() { _recovery = false; _error = null; }),
          child: const Text('Back'),
        ),
      ];

  // Recover and set the new passphrase in one step — done BEFORE the unlock
  // flips the app gate, so it doesn't depend on this screen staying mounted.
  Future<void> _recover(PortfolioStore store) async {
    if (_newPass.text.isEmpty) {
      setState(() => _error = 'Enter a new passphrase');
      return;
    }
    if (_newPass.text != _newPass2.text) {
      setState(() => _error = 'Passphrases don\'t match');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await store.recoverWithCode(_code.text);
    if (ok) await store.changePassphrase(_newPass.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!ok) _error = 'Invalid recovery code';
    });
  }

  Future<void> _forgetReset(PortfolioStore store) async {
    final ok = await confirmTyped(
      context,
      title: 'Forget & reset?',
      message: '⚠️ Without your passphrase or recovery code, the encrypted data '
          'cannot be recovered. This permanently deletes the locally stored '
          'portfolio and turns encryption off.',
      phrase: 'reset',
      confirmLabel: 'Forget & reset',
      destructive: true,
    );
    if (ok) await store.clearLocal();
  }
}
