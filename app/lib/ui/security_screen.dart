// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: LicenseRef-Proprietary
// Security settings: enable/disable encryption, change passphrase, regenerate
// the recovery code, biometric toggle, stay-unlocked duration, and Lock now.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../data/portfolio_store.dart';
import 'confirm.dart';

class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key});

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  bool _bioSupported = false;

  @override
  void initState() {
    super.initState();
    context.read<PortfolioStore>().biometric.isSupported().then((v) {
      if (mounted) setState(() => _bioSupported = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<PortfolioStore>();
    final on = store.encryptionEnabled;
    return Scaffold(
      appBar: AppBar(title: const Text('Security')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('Encrypt my portfolio'),
            subtitle: Text(on
                ? 'Data is encrypted at rest on this device.'
                : 'Off — data is stored in your browser unencrypted.'),
            value: on,
            onChanged: (v) => v ? _enable(store) : _disable(store),
          ),
          if (on) ...[
            const Divider(),
            ListTile(
              leading: const Icon(Icons.password),
              title: const Text('Change passphrase'),
              onTap: () => _changePassphrase(store),
            ),
            ListTile(
              leading: const Icon(Icons.vpn_key),
              title: const Text('Regenerate recovery code'),
              subtitle: const Text('Invalidates the old code'),
              onTap: () => _regenerate(store),
            ),
            if (_bioSupported)
              SwitchListTile(
                secondary: const Icon(Icons.fingerprint),
                title: const Text('Unlock with Touch ID / Face ID'),
                value: store.biometricEnabled,
                onChanged: (v) => v ? _enableBio(store) : store.disableBiometric(),
              ),
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: const Text('Keep this device unlocked'),
              trailing: DropdownButton<int>(
                value: const [1, 7, 30].contains(store.stayUnlockedDays)
                    ? store.stayUnlockedDays
                    : 30,
                items: const [
                  DropdownMenuItem(value: 1, child: Text('1 day')),
                  DropdownMenuItem(value: 7, child: Text('7 days')),
                  DropdownMenuItem(value: 30, child: Text('30 days')),
                ],
                onChanged: (v) => v == null ? null : store.setStayUnlockedDays(v),
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.lock),
              title: const Text('Lock now'),
              onTap: () async {
                await store.lock();
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _enable(PortfolioStore store) async {
    final pass = await _askPassphrase('Set a passphrase', 'Passphrase');
    if (pass == null || pass.isEmpty) return;
    final code = await store.enableEncryption(pass);
    if (mounted) await _showRecoveryCode(code);
  }

  Future<void> _disable(PortfolioStore store) async {
    final ok = await confirmTyped(
      context,
      title: 'Turn off encryption?',
      message: 'Your portfolio will be stored unencrypted in this browser again.',
      phrase: 'disable',
      confirmLabel: 'Turn off',
      destructive: true,
      verifyPassphrase: store.verifyPassphrase,
      verifyBiometric: store.biometricEnabled ? store.verifyBiometric : null,
      verifyRecoveryCode: store.verifyRecoveryCode,
    );
    if (ok) await store.disableEncryption();
  }

  Future<void> _changePassphrase(PortfolioStore store) async {
    final pass = await _askPassphrase('New passphrase', 'New passphrase');
    if (pass == null || pass.isEmpty) return;
    await store.changePassphrase(pass);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Passphrase changed')));
    }
  }

  Future<void> _regenerate(PortfolioStore store) async {
    final ok = await confirmTyped(
      context,
      title: 'Regenerate recovery code?',
      message: 'The current recovery code will stop working. Save the new one.',
      phrase: 'regenerate',
      confirmLabel: 'Regenerate',
    );
    if (!ok) return;
    final code = await store.regenerateRecoveryCode();
    if (mounted && code != null) await _showRecoveryCode(code);
  }

  Future<void> _enableBio(PortfolioStore store) async {
    final ok = await store.enableBiometric();
    if (mounted && !ok) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Biometric setup cancelled or unavailable')));
    }
  }

  // Requires the passphrase twice (match-validated) so a typo can't lock you out.
  Future<String?> _askPassphrase(String title, String label) {
    final pass = TextEditingController();
    final confirm = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        String? error;
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            void submit() {
              if (pass.text.isEmpty) {
                setLocal(() => error = 'Enter a passphrase');
              } else if (pass.text != confirm.text) {
                setLocal(() => error = 'Passphrases don\'t match');
              } else {
                Navigator.pop(ctx, pass.text);
              }
            }

            return AlertDialog(
              title: Text(title),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: pass,
                    obscureText: true,
                    autofocus: true,
                    decoration: InputDecoration(
                        labelText: label, border: const OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirm,
                    obscureText: true,
                    onSubmitted: (_) => submit(),
                    decoration: InputDecoration(
                        labelText: 'Confirm $label',
                        border: const OutlineInputBorder(),
                        errorText: error),
                  ),
                ],
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                FilledButton(onPressed: submit, child: const Text('OK')),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showRecoveryCode(String code) => showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text('Your recovery code'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                  '⚠️ Save this now. It is the ONLY way back in if you forget your '
                  'passphrase — there is no email reset.'),
              const SizedBox(height: 16),
              SelectableText(code,
                  style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5)),
            ],
          ),
          actions: [
            Builder(
              builder: (ctx) => TextButton.icon(
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('Copy'),
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(ctx);
                  await Clipboard.setData(ClipboardData(text: code));
                  messenger.showSnackBar(
                      const SnackBar(content: Text('Recovery code copied')));
                },
              ),
            ),
            FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('I saved it')),
          ],
        ),
      );
}
