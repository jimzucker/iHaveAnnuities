// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: Apache-2.0
// Plain-language explainer + the disclosures this app is required to show.

import 'package:flutter/material.dart';

import 'format.dart';

class InfoPage extends StatelessWidget {
  const InfoPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('About & Disclosures')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text('iHaveAnnuities', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(
                'A personal tracker for structured-product annuities — the kind '
                'whose return is linked to a market index with a cap or '
                'participation rate on the upside and one of three forms of '
                'downside protection.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),

              _Section(title: 'What it does', children: [
                _Para(
                    'Enter the terms of each contract — index, cap, participation '
                    'rate, floor, strike, and dates — and the app projects where '
                    'each one stands today and at its next reset using current '
                    'index levels. You can import or export your holdings as an '
                    '.xlsx spreadsheet that opens in Excel.'),
              ]),

              _Section(title: 'How the downside protection works', children: [
                _Bullet(
                    label: 'Floor (max-loss)',
                    color: protectionPalette('Floor', cs).accent,
                    text:
                        'You lose only down to the floor, never worse. A 0% floor '
                        'means no loss at all; a −10% floor caps the loss at 10%. '
                        'Upside still applies (subject to cap and participation).'),
                _Bullet(
                    label: 'Hard (buffer)',
                    color: protectionPalette('Hard', cs).accent,
                    text:
                        'A buffer absorbs the first portion of a decline. If the '
                        'index falls 22% with a 15% buffer, you absorb only the '
                        '7% beyond it.'),
                _Bullet(
                    label: 'Soft (barrier)',
                    color: protectionPalette('Soft', cs).accent,
                    text:
                        'Fully protected unless the index falls past the barrier. '
                        'Cross it and the entire decline applies — a 35% drop '
                        'through a 30% barrier is a full 35% loss.'),
              ]),

              _Section(title: 'Where the numbers come from', children: [
                _Para(
                    'Index levels (S&P 500, Dow, Nasdaq Composite, Nasdaq-100, '
                    'and Russell 2000) are pulled from a public market feed and '
                    'refreshed once per trading day at the 5 PM ET close; if you '
                    'leave the app open it re-checks once a day after the close. '
                    'Everything else is computed from the contract terms you '
                    'enter. The "as of" date in the header shows when prices were '
                    'last updated.'),
              ]),

              _Section(title: 'Your data', children: [
                _Para(
                    'Holdings you enter stay in this browser on this device and '
                    'are never uploaded to any server. Clearing your browser data '
                    'removes them, so export an .xlsx if you want a durable copy.'),
              ]),

              const SizedBox(height: 8),
              _Disclosures(cs: cs, theme: theme),

              const SizedBox(height: 32),
              Center(
                child: Text('Copyright 2026 Jim Zucker · Apache License 2.0',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Disclosures extends StatelessWidget {
  const _Disclosures({required this.cs, required this.theme});
  final ColorScheme cs;
  final ThemeData theme;

  static const _items = <String>[
    'Not financial, investment, tax, or legal advice. This app is an '
        'educational and record-keeping tool only. Nothing here is a '
        'recommendation to buy, hold, or sell any annuity or security.',
    'Projections are illustrative estimates, not guarantees. Figures are '
        'computed from the terms you enter and current index levels; they are '
        'not predictions and actual contract values will differ.',
    'Always rely on your official documents. Your insurer\'s or issuer\'s '
        'statements, prospectus, and contract are the authoritative source for '
        'values, terms, fees, and surrender charges.',
    'Annuity guarantees depend on the issuer. Any protection, floor, buffer, '
        'or barrier is backed solely by the claims-paying ability of the '
        'issuing insurance company.',
    'Market data may be delayed or inaccurate and is provided "as is" with no '
        'warranty. Past performance does not guarantee future results.',
    'Not affiliated with or endorsed by any insurer, index provider, or '
        'financial institution named in the app. Index names are the property '
        'of their respective owners.',
    'Consult a licensed financial professional before making any decision '
        'about your annuities.',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.gavel, size: 18, color: cs.onSurfaceVariant),
            const SizedBox(width: 8),
            Text('Important disclosures',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 12),
          for (final d in _items)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('•  ', style: theme.textTheme.bodyMedium),
                Expanded(
                    child: Text(d,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: cs.onSurface, height: 1.4))),
              ]),
            ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class _Para extends StatelessWidget {
  const _Para(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.45)),
      );
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.label, required this.color, required this.text});
  final String label;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          margin: const EdgeInsets.only(top: 4, right: 10),
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        Expanded(
          child: Text.rich(TextSpan(children: [
            TextSpan(
                text: '$label — ',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.bold, color: color)),
            TextSpan(text: text, style: theme.textTheme.bodyMedium),
          ]), style: const TextStyle(height: 1.45)),
        ),
      ]),
    );
  }
}
