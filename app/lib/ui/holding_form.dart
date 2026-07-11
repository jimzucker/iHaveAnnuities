// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: Apache-2.0
// Add/edit a holding. One form for both modes; returns a Holding via pop.

import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/payoff.dart';
import 'format.dart';

class HoldingForm extends StatefulWidget {
  const HoldingForm({super.key, this.initial, this.onDelete});
  final Holding? initial;

  /// Delete this holding (edit mode only). Returns true when it was removed, so
  /// the form closes back to the list. Null hides the delete button (add mode).
  final Future<bool> Function()? onDelete;

  @override
  State<HoldingForm> createState() => _HoldingFormState();
}

class _HoldingFormState extends State<HoldingForm> {
  final _form = GlobalKey<FormState>();
  final _scroll = ScrollController();
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
  DateTime? _inception; // optional original-investment date (rolled contracts)

  @override
  void initState() {
    super.initState();
    final h = widget.initial;
    final now = DateTime(2026, 6, 14);
    _inception = h?.inceptionDate;
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
    _scroll.dispose();
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  double _n(String k) => double.tryParse(_c[k]!.text.trim()) ?? 0;

  /// Distinct, unambiguous label per floor type (the three protection kinds
  /// used to collapse two of them into one "Hard (floor/buffer)" entry).
  static String _floorTypeLabel(FloorType t) => switch (t) {
        FloorType.hard => 'Hard (buffer)',
        FloorType.soft => 'Soft (barrier)',
        FloorType.floor => 'Floor (max loss)',
        FloorType.none => 'None (full downside)',
      };

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
      // None = no downside protection; the floor value is irrelevant.
      floor: _floorType == FloorType.none ? 0.0 : _n('floor') / 100,
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
      inceptionDate: _inception,
    );
    Navigator.of(context).pop(h);
  }

  Future<void> _deletePressed() async {
    final removed = await widget.onDelete!.call();
    if (removed && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.initial != null;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'Edit holding' : 'Add holding'), actions: [
        // Delete lives in the header (edit mode only) so it's always visible
        // without scrolling — still gated by the typed-confirm guard.
        if (editing && widget.onDelete != null) ...[
          IconButton(
            tooltip: 'Delete holding',
            icon: Icon(Icons.delete_outline, color: cs.error),
            onPressed: _deletePressed,
          ),
          const SizedBox(width: 12),
        ],
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: TextButton(onPressed: _save, child: const Text('SAVE')),
        ),
      ]),
      // Cap the form to a readable column and centre it — full-width fields on a
      // wide desktop become unscannable ~1000px slabs. The scrollbar is hidden
      // (wheel/trackpad still scroll) so the column's left and right margins are
      // exactly equal — an overlay scrollbar otherwise rides the right margin and
      // makes that side read tighter than the left.
      body: Form(
        key: _form,
        child: ScrollConfiguration(
          behavior:
              ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: SingleChildScrollView(
            controller: _scroll,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 700),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
            _section('Identity'),
            _text('issuer', 'Issuer', required: true,
                helper: 'Company that issued the note'),
            _pair(
              _dropdown<String>('Index', _index, _indexOptions,
                  (v) => setState(() => _index = v!), (v) => v,
                  helper: 'Market index it tracks'),
              _dropdown<AccountType>('Account / Type', _account,
                  AccountType.values, (v) => setState(() => _account = v!),
                  (v) => v.label,
                  helper: 'Tax treatment of the money'),
            ),

            _section('Terms'),
            _pair(
              _num('strike', 'Strike', positive: true,
                  helper: 'Index level returns start from'),
              _num('participation', 'Participation %',
                  helper: 'Share of the gain (100% = all)'),
            ),
            _pair(
              // Uncapped hides the cap field; keep the checkbox in view either way.
              _uncapped
                  ? _staticField('No cap applied',
                      helper: 'Upside is unlimited')
                  : _num('cap', 'Cap %', helper: 'Most you can earn per term'),
              _checkbox('Uncapped', _uncapped,
                  (v) => setState(() => _uncapped = v),
                  hint: 'No ceiling on the credited gain'),
            ),
            // Floor type and its floor % live together — picking None hides the %.
            _pair(
              _dropdown<FloorType>('Floor type', _floorType, FloorType.values,
                  (v) => setState(() => _floorType = v!), _floorTypeLabel,
                  helper: 'How downside is cushioned'),
              _floorType == FloorType.none
                  ? _staticField('No downside floor',
                      helper: 'You take the full loss')
                  : _num('floor', 'Floor % (≤ 0)', max0: true,
                      helper: 'How deep, e.g. -15'),
            ),
            _hintLine('Buffer/barrier absorb the first drop; floor caps the '
                'maximum loss; none = full downside.'),

            _section('Schedule'),
            _pair(
              _dateField('Start Date', _open, (d) => setState(() => _open = d),
                  helper: 'When the contract began'),
              _dateField('Maturity', _maturity,
                  (d) => setState(() => _maturity = d),
                  helper: 'When it ends'),
            ),
            _pair(
              _dropdown<ResetFreq>('Reset Freq', _reset, ResetFreq.values,
                  (v) => setState(() => _reset = v!), (v) => v.label,
                  helper: 'How often gains lock in'),
              _dateField('Next Reset', _nextReset,
                  (d) => setState(() => _nextReset = d),
                  helper: 'This term ends'),
            ),
            _pair(
              _dateField('Last Reset', _lastReset,
                  (d) => setState(() => _lastReset = d),
                  helper: 'This term began'),
              // Optional — original investment date for a rolled contract; drives
              // Yield/CAGR. Blank = use Start.
              _inceptionField(),
            ),

            _section('Value'),
            _pair(
              _num('initial', 'Initial (\$000)', positive: true,
                  helper: 'Amount invested, in thousands'),
              _num('realized', 'Realized (\$000)',
                  helper: 'Gains already taken, thousands'),
            ),

            _section('Income note'),
            _checkbox('Income note (coupon)', _note,
                (v) => setState(() => _note = v),
                hint: 'Pays periodic coupons instead of index growth — '
                    'check to enter a projected coupon.'),
            if (_note)
              _num('coupon', 'Coupon proj % @ reset',
                  helper: 'Coupon expected at each reset'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── shared field styling ──────────────────────────────────────────────────
  // One decoration for every field type (text, number, dropdown, date) so 2-up
  // rows are exactly the same height. helperText, when present, reserves a line
  // below the border — pass helper:' ' on a paired field to keep both aligned.
  static const _fieldPad = EdgeInsets.symmetric(vertical: 6);
  static const _contentPad = EdgeInsets.symmetric(horizontal: 12, vertical: 16);

  InputDecoration _dec(String label, {String? helper}) => InputDecoration(
        labelText: label,
        helperText: helper,
        border: const OutlineInputBorder(),
        contentPadding: _contentPad,
      );

  Widget _text(String k, String label, {bool required = false, String? helper}) => Padding(
        padding: _fieldPad,
        child: TextFormField(
          controller: _c[k],
          decoration: _dec(label, helper: helper),
          validator: required
              ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null
              : null,
        ),
      );

  Widget _num(String k, String label,
          {bool positive = false, bool max0 = false, String? helper}) =>
      Padding(
        padding: _fieldPad,
        child: TextFormField(
          controller: _c[k],
          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
          decoration: _dec(label, helper: helper),
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
          ValueChanged<T?> onChanged, String Function(T) labelOf,
          {String? helper}) =>
      Padding(
        padding: _fieldPad,
        child: DropdownButtonFormField<T>(
          initialValue: value,
          isExpanded: true, // ellipsize long labels instead of overflowing a 2-up row
          decoration: _dec(label, helper: helper),
          items: [for (final i in items) DropdownMenuItem(value: i, child: Text(labelOf(i)))],
          onChanged: onChanged,
        ),
      );

  /// Read-only field-shaped placeholder (e.g. when Uncapped hides Cap), so the
  /// row keeps its two equal columns instead of collapsing.
  Widget _staticField(String text, {String? helper}) => Padding(
        padding: _fieldPad,
        child: InputDecorator(
          decoration: InputDecoration(
            helperText: helper,
            border: const OutlineInputBorder(),
            contentPadding: _contentPad,
          ),
          child: Text(text,
              style: TextStyle(
                  fontStyle: FontStyle.italic,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
      );

  /// Field-height checkbox so it lines up with the input beside it in a 2-up row.
  /// With a [hint] it grows to fit a subtitle (used for full-width checkboxes).
  Widget _checkbox(String label, bool value, ValueChanged<bool> onChanged,
      {String? hint}) {
    final cs = Theme.of(context).colorScheme;
    final row = Row(children: [
      Checkbox(value: value, onChanged: (v) => onChanged(v ?? false)),
      Expanded(
        child: hint == null
            ? Text(label)
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label),
                  const SizedBox(height: 2),
                  Text(hint,
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                ],
              ),
      ),
    ]);
    return Padding(
      padding: _fieldPad,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: () => onChanged(!value),
        child: hint == null
            ? SizedBox(height: 56, child: row)
            : Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: row),
      ),
    );
  }

  /// Full-width caption under a row, for a short plain-language explainer.
  Widget _hintLine(String text) => Padding(
        padding: const EdgeInsets.only(left: 4, top: 2, bottom: 2),
        child: Text(text,
            style: TextStyle(
                fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );

  /// Two fields side by side with a consistent gutter (or one field, full width).
  Widget _pair(Widget left, [Widget? right]) => right == null
      ? left
      : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: left),
          const SizedBox(width: 14),
          Expanded(child: right),
        ]);

  /// Small-caps section header with a trailing hairline, to chunk the long form.
  Widget _section(String label) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 2),
      child: Row(children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.9,
            color: cs.primary,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Divider(color: cs.outlineVariant, height: 1)),
      ]),
    );
  }

  /// Compact date field styled like the text/dropdown inputs so it sits 2-up.
  /// The calendar sits inside the child row (not as suffixIcon) so it doesn't
  /// inflate the field's height past the text inputs.
  Widget _dateField(String label, DateTime value, ValueChanged<DateTime> onPick,
          {String? helper}) =>
      Padding(
        padding: _fieldPad,
        child: InkWell(
          onTap: () => _pickDate(value, onPick),
          child: InputDecorator(
            decoration: _dec(label, helper: helper),
            child: Row(children: [
              Expanded(child: Text(date(value))),
              Icon(Icons.calendar_today,
                  size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ]),
          ),
        ),
      );

  /// Optional inception date — same compact field, with a clear affordance and
  /// a hint that a blank value falls back to Start for Yield/CAGR.
  Widget _inceptionField() {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: _fieldPad,
      child: InkWell(
        onTap: () => _pickDate(
            _inception ?? _open, (d) => setState(() => _inception = d)),
        child: InputDecorator(
          decoration: _dec('Inception (optional)',
              helper: _inception == null ? 'Yield uses Start' : ' '),
          child: Row(children: [
            Expanded(
              child: Text(_inception == null ? 'Not set' : date(_inception!),
                  style: _inception == null
                      ? TextStyle(color: cs.onSurfaceVariant)
                      : null),
            ),
            if (_inception != null)
              InkWell(
                onTap: () => setState(() => _inception = null),
                child: Icon(Icons.clear, size: 18, color: cs.onSurfaceVariant),
              )
            else
              Icon(Icons.calendar_today, size: 18, color: cs.onSurfaceVariant),
          ]),
        ),
      ),
    );
  }
}
