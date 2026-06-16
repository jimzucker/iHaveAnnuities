// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: Apache-2.0
// One combined index chart: every index rebased to % change over the selected
// range (so different price scales compare), with a tappable legend to hide/
// show indexes (remembered) and 1D…Max range toggles. Data comes from the
// Action-generated data/history.json (same-origin fetch avoids CORS).

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../data/index_history.dart';
import '../data/portfolio_store.dart';
import 'format.dart';

const _indexes = <(String, String)>[
  ('SPX', 'S&P 500'),
  ('DJI', 'Dow'),
  ('COMP', 'Nasdaq Comp'),
  ('NDX', 'Nasdaq-100'),
  ('RUT', 'Russell 2000'),
];
const _indexColor = <String, Color>{
  'SPX': Color(0xFF1F6FEB),
  'DJI': Color(0xFF18A999),
  'COMP': Color(0xFF8957E5),
  'NDX': Color(0xFFE0A030),
  'RUT': Color(0xFF2EA043),
};

class IndexChartScreen extends StatefulWidget {
  const IndexChartScreen({super.key, this.base = '', this.client});

  final String base;
  final http.Client? client;

  @override
  State<IndexChartScreen> createState() => _IndexChartScreenState();
}

class _IndexChartScreenState extends State<IndexChartScreen> {
  IndexHistory? _hist;
  String? _error;
  HistoryRange _range = HistoryRange.oneM;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final h = await IndexHistory.fetch(base: widget.base, client: widget.client);
      if (mounted) setState(() => _hist = h);
    } catch (e) {
      if (mounted) setState(() => _error = 'History unavailable ($e)');
    }
  }

  /// Rebased (% from range start) series per visible index.
  List<({String sym, Color color, List<(DateTime, double)> pts})> _visible(
      Set<String> hidden) {
    final out = <({String sym, Color color, List<(DateTime, double)> pts})>[];
    for (final (sym, _) in _indexes) {
      if (hidden.contains(sym)) continue;
      final raw = _hist?.series(sym, _range) ?? const [];
      if (raw.isEmpty) continue;
      final base = raw.first.$2;
      if (base == 0) continue;
      out.add((
        sym: sym,
        color: _indexColor[sym]!,
        pts: [for (final p in raw) (p.$1, p.$2 / base - 1)],
      ));
    }
    return out;
  }

  double? _change(String sym) {
    final raw = _hist?.series(sym, _range) ?? const [];
    if (raw.isEmpty || raw.first.$2 == 0) return null;
    return raw.last.$2 / raw.first.$2 - 1;
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<PortfolioStore>();
    final cs = Theme.of(context).colorScheme;
    final hidden = store.hiddenIndexes;
    final series = _visible(hidden);

    return Scaffold(
      appBar: AppBar(title: const Text('Indexes')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<HistoryRange>(
              showSelectedIcon: false,
              segments: [
                for (final r in HistoryRange.values)
                  ButtonSegment(value: r, label: Text(r.label)),
              ],
              selected: {_range},
              onSelectionChanged: (s) => setState(() => _range = s.first),
            ),
          ),
          const SizedBox(height: 12),
          // Tappable legend — tap to hide/show an index (remembered).
          Wrap(spacing: 8, runSpacing: 6, children: [
            for (final (sym, label) in _indexes)
              _LegendChip(
                label: label,
                color: _indexColor[sym]!,
                change: _change(sym),
                off: hidden.contains(sym),
                onTap: () => store.toggleIndex(sym),
              ),
          ]),
          const SizedBox(height: 12),
          if (_error != null)
            Text(_error!, style: TextStyle(color: cs.error))
          else if (_hist == null)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (series.isEmpty)
            const Expanded(child: Center(child: Text('No indexes selected')))
          else
            Expanded(
              child: CustomPaint(
                painter: _MultiLinePainter(series, cs, _range.label),
                child: const SizedBox.expand(),
              ),
            ),
        ]),
      ),
    );
  }
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({
    required this.label,
    required this.color,
    required this.change,
    required this.off,
    required this.onTap,
  });
  final String label;
  final Color color;
  final double? change;
  final bool off;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: off ? cs.surfaceContainerHighest : color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: off ? cs.outlineVariant : color, width: 1),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                  color: off ? cs.outline : color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  decoration: off ? TextDecoration.lineThrough : null,
                  color: off ? cs.onSurfaceVariant : cs.onSurface)),
          if (!off && change != null) ...[
            const SizedBox(width: 6),
            Text(pctSigned(change!),
                style: TextStyle(fontSize: 12, color: gainColor(change!, cs))),
          ],
        ]),
      ),
    );
  }
}

class _MultiLinePainter extends CustomPainter {
  _MultiLinePainter(this.series, this.cs, this.rangeLabel);
  final List<({String sym, Color color, List<(DateTime, double)> pts})> series;
  final ColorScheme cs;
  final String rangeLabel;

  @override
  void paint(Canvas canvas, Size size) {
    const padL = 48.0, padR = 12.0, padT = 10.0, padB = 8.0;
    final w = size.width - padL - padR;
    final ht = size.height - padT - padB;

    double yLo = 0, yHi = 0, t0 = double.infinity, t1 = -double.infinity;
    for (final s in series) {
      for (final p in s.pts) {
        yLo = yLo < p.$2 ? yLo : p.$2;
        yHi = yHi > p.$2 ? yHi : p.$2;
        final t = p.$1.millisecondsSinceEpoch.toDouble();
        t0 = t < t0 ? t : t0;
        t1 = t > t1 ? t : t1;
      }
    }
    final ySpan = (yHi - yLo) == 0 ? 0.02 : (yHi - yLo);
    yHi += ySpan * 0.1;
    yLo -= ySpan * 0.1;
    final tSpan = (t1 - t0) == 0 ? 1.0 : (t1 - t0);

    double sx(DateTime t) => padL + (t.millisecondsSinceEpoch - t0) / tSpan * w;
    double sy(double v) => padT + (yHi - v) / (yHi - yLo) * ht;

    final grid = Paint()
      ..color = cs.outlineVariant.withValues(alpha: 0.4)
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final v = yLo + (yHi - yLo) * i / 4;
      final y = sy(v);
      canvas.drawLine(Offset(padL, y), Offset(padL + w, y),
          v.abs() < 1e-9 ? (grid..color = cs.outlineVariant) : grid);
      _txt(canvas, '${(v * 100).round()}%', Offset(padL - 6, y - 6));
    }

    for (final s in series) {
      final path = Path();
      for (var i = 0; i < s.pts.length; i++) {
        final o = Offset(sx(s.pts[i].$1), sy(s.pts[i].$2));
        i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(
          path,
          Paint()
            ..color = s.color
            ..strokeWidth = 2
            ..style = PaintingStyle.stroke);
    }
  }

  void _txt(Canvas canvas, String s, Offset at) {
    final tp = TextPainter(
      text: TextSpan(
          text: s, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 10)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(at.dx - tp.width, at.dy));
  }

  @override
  bool shouldRepaint(covariant _MultiLinePainter old) =>
      old.series != series || old.rangeLabel != rangeLabel;
}
