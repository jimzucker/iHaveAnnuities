// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: Apache-2.0
// In-app user guide: a column glossary plus short explainers for the metrics,
// protection types, reset cadence, and security — styled as section cards that
// match the rest of the app. Reachable from the overflow menu; pairs with the
// column-header tooltips for inline help.

import 'package:flutter/material.dart';

import 'format.dart';

class GuideScreen extends StatelessWidget {
  const GuideScreen({super.key});

  static const _columns = <(String, String)>[
    ('Initial', 'Principal you put in (\$000).'),
    ('Realized', 'Income/gains already banked from prior reset periods (\$000).'),
    ('Unrealized \$', 'Gain/loss not yet credited — the current period\'s projected payoff.'),
    ('Total Value', 'Projected value at the next reset using today\'s levels: '
        'Initial + Realized + Unrealized.'),
    ('Return %', 'All-in return on principal: (Total Value − Initial) / Initial. Cumulative.'),
    ('Unrealized %', 'Current period\'s projected payoff as a % of principal.'),
    ('Index Gain', 'How far the underlying index has moved since the strike.'),
    ('Yield', 'Life-to-date annualized return (CAGR) from the start date; '
        'shows the cumulative return for holdings under a year.'),
    ('Inception', 'Original investment date for a contract that rolled from a prior '
        'period. When set, Yield/CAGR measures from here instead of Start Date.'),
    ('Start Date', 'When the current period began (the most recent roll/open).'),
    ('Protection', 'Downside type + floor: Floor / Hard / Soft / None.'),
    ('Cap', 'Maximum credited gain (or Uncapped).'),
    ('Part.', 'Participation rate applied to the index move.'),
    ('Floor', 'The downside level (≤ 0%).'),
    ('Strike', 'Index level the return is measured from.'),
    ('Reset Freq', 'How often it credits: Once (point-to-point), Annual, or Monthly.'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('User Guide')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Card(
            icon: Icons.view_column_outlined,
            title: 'Columns',
            child: _Glossary(entries: _columns),
          ),
          _Card(
            icon: Icons.trending_up,
            title: 'Yield vs. portfolio XIRR',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _para(theme,
                    'Per-contract Yield is a life-to-date CAGR — the annualized '
                    'return since the start (or Inception, if set). Under a year it '
                    'shows the plain cumulative return, since annualizing a few weeks '
                    'overstates.'),
                const SizedBox(height: 8),
                _para(theme,
                    'The hero\'s Total Value shows a money-weighted XIRR for the whole '
                    'book — each holding\'s principal as an outflow at its own start '
                    'date, today\'s value as the inflow — so contracts opened on '
                    'different dates combine correctly.'),
              ],
            ),
          ),
          _Card(
            icon: Icons.shield_outlined,
            title: 'Protection types',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ProtChip('Floor', cs,
                    'Max-loss floor — you lose only down to the floor (0% = no loss).'),
                _ProtChip('Hard', cs,
                    'Buffer — absorbs the first |floor|% of losses; you lose beyond it.'),
                _ProtChip('Soft', cs,
                    'Barrier — fully protected unless the index breaches it, then full loss.'),
                _ProtChip('None', cs,
                    'No protection — you take the full index loss, 1:1.'),
              ],
            ),
          ),
          _Card(
            icon: Icons.event_repeat,
            title: 'Reset cadence',
            child: _Glossary(entries: const [
              ('Once', 'Point-to-point — one observation, credited at maturity.'),
              ('Annual', 'Credits and resets the strike every year.'),
              ('Monthly', 'Credits and resets the strike every month (income notes).'),
            ]),
          ),
          _Card(
            icon: Icons.lock_outline,
            title: 'Privacy & security',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _para(theme,
                    'Your portfolio stays in this browser — no account, no server. You '
                    'can encrypt it (AES-256) behind a passphrase, and unlock with the '
                    'passphrase, Touch ID / Face ID, or a one-time recovery code.'),
                const SizedBox(height: 8),
                _para(theme,
                    'There is no email reset: if you lose both the passphrase and the '
                    'recovery code, the encrypted data can\'t be recovered — keep an '
                    'exported .xlsx as your backup.'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Widget _para(ThemeData theme, String t) => Text(t,
      style: theme.textTheme.bodyMedium?.copyWith(height: 1.45));
}

/// A titled section card matching the app's surface/outline idiom.
class _Card extends StatelessWidget {
  const _Card({required this.icon, required this.title, required this.child});
  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 18, color: cs.primary),
          const SizedBox(width: 8),
          Text(title,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 12),
        child,
      ]),
    );
  }
}

/// A term/definition list: the term in a tinted monospace-ish chip, the body
/// in body text beside it. Reads like a reference, not a paragraph dump.
class _Glossary extends StatelessWidget {
  const _Glossary({required this.entries});
  final List<(String, String)> entries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      children: [
        for (var i = 0; i < entries.length; i++) ...[
          if (i > 0) Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: 104,
                child: Text(entries[i].$1,
                    style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700, color: cs.primary)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(entries[i].$2,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.4)),
              ),
            ]),
          ),
        ],
      ],
    );
  }
}

/// A protection-type row using the same color palette as the table pill/donut.
class _ProtChip extends StatelessWidget {
  const _ProtChip(this.name, this.cs, this.body);
  final String name;
  final ColorScheme cs;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pal = protectionPalette(name, cs);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 64,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
              color: pal.bg, borderRadius: BorderRadius.circular(12)),
          child: Text(name,
              style: TextStyle(
                  color: pal.fg, fontSize: 12, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(body,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.4)),
        ),
      ]),
    );
  }
}
