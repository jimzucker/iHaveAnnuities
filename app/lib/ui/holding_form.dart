// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: Apache-2.0
// Add/edit a holding. One form for both modes; returns a Holding via pop.

import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/payoff.dart';
import 'format.dart';

class HoldingForm extends StatefulWidget {
  const HoldingForm({super.key, this.initial});
  final Holding? initial;

  @override
  State<HoldingForm> createState() => _HoldingFormState();
}

class _HoldingFormState extends State<HoldingForm> {
  final _form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _c;
  late String _index;
  late AccountType _account;
  late FloorType _floorType;
  late ResetFreq _reset;
  late bool _uncapped;
  late bool _note;

  static const _indexOptions = <String>[
    'SPX', 'NDX', 'RUT', 'DOW', 'COMP', 'worst-of SPX/NDX/RUT',
  ];

  /// Map any stored index value (Yahoo ticker, short name, worst-of label) to
  /// one of [_indexOptions] so the dropdown never gets an out-of-range value.
  static String _indexOption(String? raw) {
    final u = (raw ?? 'SPX').toUpperCase();
    if (u.contains('/') || u.contains('WORST')) return 'worst-of SPX/NDX/RUT';
    if (u.contains('DJI') || u.contains('DOW')) return 'DOW';
    if (u.contains('IXIC') || u.contains('COMP')) return 'COMP';
    if (u.contains('NDX')) return 'NDX';
    if (u.contains('RUT')) return 'RUT';
    return 'SPX';
  }
  late DateTime _open, _lastReset, _maturity, _nextReset;

  @override
  void initState() {
    super.initState();
    final h = widget.initial;
    final now = DateTime(2026, 6, 14);
    _index = _indexOption(h?.index); // normalize tickers to a dropdown value
    _account = h?.account ?? AccountType.nonQual;
    _floorType = h?.floorType ?? FloorType.hard;
    _reset = h?.resetFreq ?? ResetFreq.annual;
    _uncapped = h != null && h.cap == null;
    _note = h?.isIncomeNote ?? false;
    _open = h?.openDate ?? now;
    _lastReset = h?.lastReset ?? now;
    _maturity = h?.maturity ?? DateTime(now.year + 6, now.month, now.day);
    _nextReset = h?.nextReset ?? DateTime(now.year + 1, now.month, now.day);
    _c = {
      'issuer': TextEditingController(text: h?.issuer ?? ''),
      'cap': TextEditingController(text: h?.cap == null ? '' : (h!.cap! * 100).toString()),
      'participation': TextEditingController(text: ((h?.participation ?? 1.0) * 100).toString()),
      'floor': TextEditingController(text: ((h?.floor ?? 0.0) * 100).toString()),
      'strike': TextEditingController(text: h?.strike.toString() ?? ''),
      'initial': TextEditingController(text: (h?.initial ?? 100.0).toString()),
      'realized': TextEditingController(text: (h?.realized ?? 0.0).toString()),
      'coupon': TextEditingController(text: ((h?.couponProj ?? 0.0) * 100).toString()),
    };
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  double _n(String k) => double.tryParse(_c[k]!.text.trim()) ?? 0;

  Future<void> _pickDate(DateTime current, ValueChanged<DateTime> onPick) async {
    final d = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2010),
      lastDate: DateTime(2050),
    );
    if (d != null) onPick(d);
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    final strike = _n('strike');
    final h = Holding(
      issuer: _c['issuer']!.text.trim(),
      index: _index,
      account: _account,
      cap: _uncapped ? null : _n('cap') / 100,
      participation: _n('participation') / 100,
      floor: _n('floor') / 100,
      floorType: _floorType,
      strike: strike,
      currentLevel: widget.initial?.currentLevel ?? strike,
      openDate: _open,
      lastReset: _lastReset,
      maturity: _maturity,
      nextReset: _nextReset,
      resetFreq: _reset,
      initial: _n('initial'),
      realized: _n('realized'),
      isIncomeNote: _note,
      couponProj: _note ? _n('coupon') / 100 : 0,
    );
    Navigator.of(context).pop(h);
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.initial != null;
    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'Edit holding' : 'Add holding'), actions: [
        TextButton(onPressed: _save, child: const Text('SAVE')),
      ]),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _text('issuer', 'Issuer', required: true),
            _dropdown<String>('Index', _index, _indexOptions,
                (v) => setState(() => _index = v!), (v) => v),
            _dropdown<AccountType>('Account / Type', _account, AccountType.values,
                (v) => setState(() => _account = v!), (v) => v.label),
            Row(children: [
              Expanded(
                child: CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Uncapped'),
                  value: _uncapped,
                  onChanged: (v) => setState(() => _uncapped = v ?? false),
                ),
              ),
              if (!_uncapped) Expanded(child: _num('cap', 'Cap %')),
            ]),
            Row(children: [
              Expanded(child: _num('participation', 'Participation %')),
              const SizedBox(width: 12),
              Expanded(child: _num('floor', 'Floor % (≤ 0)', max0: true)),
            ]),
            _dropdown<FloorType>('Floor type', _floorType, FloorType.values,
                (v) => setState(() => _floorType = v!),
                (v) => v == FloorType.soft ? 'Soft (barrier)' : 'Hard (floor/buffer)'),
            Row(children: [
              Expanded(child: _num('strike', 'Strike', positive: true)),
              const SizedBox(width: 12),
              Expanded(
                child: _dropdown<ResetFreq>('Reset freq', _reset, ResetFreq.values,
                    (v) => setState(() => _reset = v!), (v) => v.label),
              ),
            ]),
            _dateTile('Open', _open, (d) => setState(() => _open = d)),
            _dateTile('Last reset', _lastReset, (d) => setState(() => _lastReset = d)),
            _dateTile('Maturity', _maturity, (d) => setState(() => _maturity = d)),
            _dateTile('Next reset', _nextReset, (d) => setState(() => _nextReset = d)),
            Row(children: [
              Expanded(child: _num('initial', 'Initial (\$000)', positive: true)),
              const SizedBox(width: 12),
              Expanded(child: _num('realized', 'Realized (\$000)')),
            ]),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Income note (coupon)'),
              value: _note,
              onChanged: (v) => setState(() => _note = v ?? false),
            ),
            if (_note) _num('coupon', 'Coupon proj % @ reset'),
          ],
        ),
      ),
    );
  }

  Widget _text(String k, String label, {bool required = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: TextFormField(
          controller: _c[k],
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
          validator: required
              ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null
              : null,
        ),
      );

  Widget _num(String k, String label, {bool positive = false, bool max0 = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: TextFormField(
          controller: _c[k],
          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
          validator: (v) {
            final d = double.tryParse((v ?? '').trim());
            if (d == null) return 'Number';
            if (positive && d <= 0) return 'Must be > 0';
            if (max0 && d > 0) return 'Must be ≤ 0';
            return null;
          },
        ),
      );

  Widget _dropdown<T>(String label, T value, List<T> items,
          ValueChanged<T?> onChanged, String Function(T) labelOf) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: DropdownButtonFormField<T>(
          initialValue: value,
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
          items: [for (final i in items) DropdownMenuItem(value: i, child: Text(labelOf(i)))],
          onChanged: onChanged,
        ),
      );

  Widget _dateTile(String label, DateTime value, ValueChanged<DateTime> onPick) => ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        subtitle: Text(date(value)),
        trailing: const Icon(Icons.calendar_today, size: 18),
        onTap: () => _pickDate(value, onPick),
      );
}
