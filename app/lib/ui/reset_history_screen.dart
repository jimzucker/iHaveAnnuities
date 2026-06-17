// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: Apache-2.0
// A reference log of resets the app applied automatically: income-note coupons
// credited and point-to-point periods locked in as their reset dates passed.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/reset_event.dart';
import '../data/portfolio_store.dart';
import 'format.dart';

class ResetHistoryScreen extends StatelessWidget {
  const ResetHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<PortfolioStore>();
    final events = store.resetHistory; // newest first
    return Scaffold(
      appBar: AppBar(title: const Text('Reset History')),
      body: events.isEmpty
          ? const _Empty()
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: events.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) => _ResetCard(e: events[i]),
            ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.event_repeat, size: 40, color: cs.onSurfaceVariant),
          const SizedBox(height: 8),
          Text('No resets recorded yet',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'When a holding’s reset date passes, the app credits the coupon '
            '(income notes) or locks in the period’s index gain '
            '(point-to-point) and logs it here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ]),
      ),
    );
  }
}

class _ResetCard extends StatelessWidget {
  const _ResetCard({required this.e});
  final ResetEvent e;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final gc = gainColor(e.realizedAddedK, cs);
    final kind = e.isIncomeNote
        ? (e.missed ? 'Coupon missed' : 'Coupon')
        : 'Index reset';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(e.label,
                  style: tt.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
            ),
            Text(date(e.date),
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 20, runSpacing: 8, children: [
            _kv(cs, kind, pctSigned(e.periodReturn),
                color: e.missed ? cs.error : null),
            if (!e.missed)
              _kv(cs, 'Credited', '${e.realizedAddedK >= 0 ? '+' : ''}'
                  '${moneyK(e.realizedAddedK)}', color: gc),
            if (e.missed)
              _kv(cs, 'Barrier', 'breached', color: cs.error),
            if (!e.isIncomeNote && e.oldStrike != null && e.newStrike != null)
              _kv(cs, 'Strike', '${level(e.oldStrike!)} → ${level(e.newStrike!)}'),
            _kv(cs, 'Realized after', moneyK(e.realizedAfterK)),
          ]),
        ]),
      ),
    );
  }

  Widget _kv(ColorScheme cs, String k, String v, {Color? color}) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          Text(v,
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600, color: color)),
        ],
      );
}
