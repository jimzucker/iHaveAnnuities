// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: Apache-2.0
// Tap-through index price chart with range toggles (1D … Max), fed by the
// Action-generated data/history.json.

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../data/index_history.dart';
import 'format.dart';

class IndexChartScreen extends StatefulWidget {
  const IndexChartScreen({
    super.key,
    required this.symbol,
    required this.label,
    this.base = '',
    this.client,
  });

  final String symbol;
  final String label;
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pts = _hist?.series(widget.symbol, _range) ?? const <SeriesPoint>[];
    return Scaffold(
      appBar: AppBar(title: Text(widget.label)),
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
          const SizedBox(height: 14),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Text(_error!, style: TextStyle(color: cs.error)),
            )
          else if (_hist == null)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (pts.isEmpty)
            const Expanded(child: Center(child: Text('No data for this range')))
          else ...[
            _summary(pts, cs),
            const SizedBox(height: 10),
            Expanded(
              child: CustomPaint(
                painter: _LinePainter(pts, cs),
                child: const SizedBox.expand(),
              ),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _summary(List<SeriesPoint> pts, ColorScheme cs) {
    final first = pts.first.$2, last = pts.last.$2;
    final chg = first == 0 ? 0.0 : (last / first - 1);
    final c = gainColor(chg, cs);
    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Text(level(last),
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
      const SizedBox(width: 10),
      Text('${chg >= 0 ? '▲' : '▼'} ${pctSigned(chg)}  ·  ${_range.label}',
          style: TextStyle(color: c, fontWeight: FontWeight.w600)),
    ]);
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.pts, this.cs);
  final List<SeriesPoint> pts;
  final ColorScheme cs;

  @override
  void paint(Canvas canvas, Size size) {
    const padL = 56.0, padR = 12.0, padT = 10.0, padB = 8.0;
    final w = size.width - padL - padR;
    final ht = size.height - padT - padB;

    var lo = pts.first.$2, hi = pts.first.$2;
    for (final p in pts) {
      lo = lo < p.$2 ? lo : p.$2;
      hi = hi > p.$2 ? hi : p.$2;
    }
    final span = (hi - lo) == 0 ? (hi == 0 ? 1.0 : hi.abs() * 0.02) : (hi - lo);
    final yLo = lo - span * 0.08, yHi = hi + span * 0.08;
    final t0 = pts.first.$1.millisecondsSinceEpoch.toDouble();
    final t1 = pts.last.$1.millisecondsSinceEpoch.toDouble();
    final tSpan = (t1 - t0) == 0 ? 1.0 : (t1 - t0);

    double sx(DateTime t) => padL + (t.millisecondsSinceEpoch - t0) / tSpan * w;
    double sy(double v) => padT + (yHi - v) / (yHi - yLo) * ht;

    final grid = Paint()
      ..color = cs.outlineVariant.withValues(alpha: 0.4)
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final v = yLo + (yHi - yLo) * i / 3;
      final y = sy(v);
      canvas.drawLine(Offset(padL, y), Offset(padL + w, y), grid);
      _txt(canvas, level(v), Offset(padL - 6, y - 6));
    }

    final path = Path();
    for (var i = 0; i < pts.length; i++) {
      final o = Offset(sx(pts[i].$1), sy(pts[i].$2));
      i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
    }
    final up = pts.last.$2 >= pts.first.$2;
    final color = up ? gainGreen : lossRed;
    final fill = Path.from(path)
      ..lineTo(sx(pts.last.$1), padT + ht)
      ..lineTo(sx(pts.first.$1), padT + ht)
      ..close();
    canvas.drawPath(fill, Paint()..color = color.withValues(alpha: 0.10));
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke);
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
  bool shouldRepaint(covariant _LinePainter old) => old.pts != pts;
}
