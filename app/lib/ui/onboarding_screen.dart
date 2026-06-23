// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: Apache-2.0
// First-run security wizard: shown once on a brand-new install, BEFORE any data
// exists. Lets the user opt into encryption, forces them to save the recovery
// code (the only way back — there's no email reset), and optionally enrolls
// biometric. "Skip for now" leaves the data unencrypted (changeable later).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../data/portfolio_store.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _step = 0;
  final _pass = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;
  bool _busy = false;
  bool _acked = false;
  bool _bioSupported = false;
  String? _recoveryCode;

  @override
  void initState() {
    super.initState();
    context.read<PortfolioStore>().biometric.isSupported().then((v) {
      if (mounted) setState(() => _bioSupported = v);
    });
  }

  @override
  void dispose() {
    _pass.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _finish() => context.read<PortfolioStore>().markOnboarded();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: switch (_step) {
                0 => _welcome(),
                1 => _passphrase(),
                2 => _recovery(),
                _ => _biometric(),
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _welcome() {
    final cs = Theme.of(context).colorScheme;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.shield_outlined, size: 56, color: cs.primary),
      const SizedBox(height: 16),
      Text('Protect your portfolio',
          style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
      const SizedBox(height: 12),
      const Text(
        'Your data is stored only in this browser — it never leaves your device '
        'and there is no account or server. You can encrypt it with a passphrase '
        'so no one else using this computer can read it.',
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 24),
      FilledButton(
        onPressed: () => setState(() => _step = 1),
        child: const Text('Set up encryption'),
      ),
      const SizedBox(height: 8),
      TextButton(
        onPressed: () async {
          await _finish(); // skip — stays unencrypted, enable later in Security
        },
        child: const Text('Skip for now'),
      ),
    ]);
  }

  Widget _passphrase() {
    final cs = Theme.of(context).colorScheme;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Create a passphrase',
          style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
      const SizedBox(height: 16),
      TextField(
        controller: _pass,
        obscureText: true,
        autofocus: true,
        enabled: !_busy,
        decoration: const InputDecoration(labelText: 'Passphrase', border: OutlineInputBorder()),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _confirm,
        obscureText: true,
        enabled: !_busy,
        decoration: const InputDecoration(labelText: 'Confirm passphrase', border: OutlineInputBorder()),
      ),
      if (_error != null) ...[
        const SizedBox(height: 12),
        Text(_error!, style: TextStyle(color: cs.error)),
      ],
      const SizedBox(height: 20),
      FilledButton(onPressed: _busy ? null : _createPassphrase, child: const Text('Continue')),
      TextButton(onPressed: _busy ? null : () => setState(() => _step = 0), child: const Text('Back')),
    ]);
  }

  Future<void> _createPassphrase() async {
    final p = _pass.text;
    if (p.isEmpty) {
      setState(() => _error = 'Enter a passphrase.');
      return;
    }
    if (p != _confirm.text) {
      setState(() => _error = 'The passphrases don\'t match.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final code = await context.read<PortfolioStore>().enableEncryption(p);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _recoveryCode = code;
      _step = 2;
    });
  }

  Widget _recovery() {
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Save your recovery code',
          style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
      const SizedBox(height: 12),
      const Text(
        '⚠️ This is the ONLY way back in if you forget your passphrase. There is '
        'no email reset. Store it somewhere safe (password manager, printed copy).',
      ),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: SelectableText(
          _recoveryCode ?? '',
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontFamily: 'monospace', fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.5),
        ),
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          icon: const Icon(Icons.copy, size: 18),
          label: const Text('Copy'),
          onPressed: () async {
            final messenger = ScaffoldMessenger.of(context);
            await Clipboard.setData(ClipboardData(text: _recoveryCode ?? ''));
            messenger.showSnackBar(const SnackBar(content: Text('Recovery code copied')));
          },
        ),
      ),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        value: _acked,
        onChanged: (v) => setState(() => _acked = v ?? false),
        title: const Text(
            'I\'ve saved it. I understand my data can\'t be recovered if I lose '
            'both my passphrase and this code.'),
      ),
      const SizedBox(height: 12),
      FilledButton(
        // With biometric available go to that step; otherwise finish now.
        onPressed: _acked
            ? () => _bioSupported ? setState(() => _step = 3) : _finish()
            : null,
        child: const Text('Continue'),
      ),
    ]);
  }

  Widget _biometric() {
    final cs = Theme.of(context).colorScheme;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Icon(Icons.fingerprint, size: 56, color: cs.primary),
      const SizedBox(height: 16),
      Text('Faster unlock?',
          style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
      const SizedBox(height: 12),
      const Text(
        'Add Touch ID / Face ID so you can unlock without typing your passphrase '
        'each time. You can change this later in Security.',
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 24),
      FilledButton.icon(
        icon: const Icon(Icons.fingerprint),
        onPressed: _busy ? null : _enableBiometric,
        label: const Text('Enable Touch ID'),
      ),
      const SizedBox(height: 8),
      TextButton(onPressed: _busy ? null : _finish, child: const Text('Not now')),
    ]);
  }

  Future<void> _enableBiometric() async {
    setState(() => _busy = true);
    final ok = await context.read<PortfolioStore>().enableBiometric();
    if (!mounted) return;
    if (!ok) {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Biometric setup cancelled or unavailable')));
      return;
    }
    await _finish();
  }
}
