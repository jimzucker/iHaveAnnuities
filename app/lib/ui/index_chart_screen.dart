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
// Your portfolio: a distinct rose, drawn thicker with a filled area so it reads
// as "mine" vs. the thin index reference lines.
const _portfolioColor = Color(0xFFEC407A);

typedef _Series = ({
  String sym,
  Color color,
  List<(DateTime, double)> pts,
  bool area, // filled area + thicker line (the portfolio)
});

// Plot padding — shared so the cursor gesture and the painter agree on geometry.
// _padB leaves room for the x-axis date labels under the plot.
const _padL = 48.0, _padR = 12.0, _padT = 10.0, _padB = 24.0;

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
  double? _cursorFrac; // 0..1 across the plot; null when not hovering/touching

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
  List<_Series> _visible(Set<String> hidden) {
    final out = <_Series>[];
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
        area: false,
      ));
    }
    return out;
  }

  /// The portfolio line: a principal-weighted blend of its holdings' underlying
  /// index returns over the range (income notes excluded — no index exposure).
  /// Tracks the underlyings, before caps/floors. Empty when there's no data.
  List<(DateTime, double)> _portfolioBlend(PortfolioStore store) {
    final hist = _hist;
    if (hist == null) return const [];
    final holdings = store.holdings.where((h) => !h.isIncomeNote).toList();
    final total = holdings.fold(0.0, (s, h) => s + h.initial);
    if (total <= 0) return const [];
    final weight = <String, double>{};
    for (final h in holdings) {
      weight[h.baseIndex] = (weight[h.baseIndex] ?? 0) + h.initial / total;
    }
    final rebased = <String, List<(DateTime, double)>>{};
    for (final sym in weight.keys) {
      final raw = hist.series(sym, _range);
      if (raw.isEmpty || raw.first.$2 == 0) return const []; // missing data
      final b = raw.first.$2;
      rebased[sym] = [for (final p in raw) (p.$1, p.$2 / b - 1)];
    }
    // All index series for a range share dates; blend index-by-index along the
    // longest one as the spine.
    final spine = rebased.values.reduce((a, b) => a.length >= b.length ? a : b);
    return [
      for (var i = 0; i < spine.length; i++)
        (
          spine[i].$1,
          [
            for (final e in rebased.entries)
              weight[e.key]! * (i < e.value.length ? e.value[i].$2 : e.value.last.$2)
          ].fold(0.0, (s, x) => s + x),
        ),
    ];
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
    // Append the portfolio blend (toggled via the 'PORTFOLIO' key, default on).
    final showPortfolio = !hidden.contains('PORTFOLIO');
    final blend = _portfolioBlend(store);
    if (showPortfolio && blend.isNotEmpty) {
      series.add((
        sym: 'PORTFOLIO',
        color: _portfolioColor,
        pts: blend,
        area: true,
      ));
    }

    final size = MediaQuery.of(context).size;
    // Portrait phones: a chart that fills the viewport stays cramped, so give it
    // 1.5× the screen height and let the page scroll (controls scroll up out of
    // the way). Wide/landscape keeps the chart filling the available height.
    final portrait = size.height > size.width && size.width < 700;

    final controls = <Widget>[
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SegmentedButton<HistoryRange>(
          showSelectedIcon: false,
          segments: [
            for (final r in HistoryRange.values)
              ButtonSegment(value: r, label: Text(r.label)),
          ],
          selected: {_range},
          onSelectionChanged: (s) => setState(() {
            _range = s.first;
            _cursorFrac = null;
          }),
        ),
      ),
      const SizedBox(height: 12),
      // Tappable legend — tap to hide/show a series (remembered).
      Wrap(spacing: 8, runSpacing: 6, children: [
        if (blend.isNotEmpty)
          _LegendChip(
            label: 'My portfolio',
            color: _portfolioColor,
            change: blend.last.$2,
            off: !showPortfolio,
            onTap: () => store.toggleIndex('PORTFOLIO'),
          ),
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
    ];

    Widget chart() => LayoutBuilder(builder: (context, box) {
          void setCursor(double dx) {
            final w = box.maxWidth - _padL - _padR;
            setState(() => _cursorFrac =
                w <= 0 ? null : ((dx - _padL) / w).clamp(0.0, 1.0));
          }

          return MouseRegion(
            onHover: (e) => setCursor(e.localPosition.dx),
            onExit: (_) => setState(() => _cursorFrac = null),
            child: GestureDetector(
              onTapDown: (d) => setCursor(d.localPosition.dx),
              onHorizontalDragStart: (d) => setCursor(d.localPosition.dx),
              onHorizontalDragUpdate: (d) => setCursor(d.localPosition.dx),
              child: CustomPaint(
                painter: _MultiLinePainter(series, cs, _range.label, _cursorFrac),
                child: const SizedBox.expand(),
              ),
            ),
          );
        });

    Widget content() => _error != null
        ? Center(child: Text(_error!, style: TextStyle(color: cs.error)))
        : _hist == null
            ? const Center(child: CircularProgressIndicator())
            : series.isEmpty
                ? const Center(child: Text('No indexes selected'))
                : chart();

    return Scaffold(
      appBar: AppBar(title: const Text('Indexes')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        // Portrait: the chart is sized to one full screen and the header sits
        // above it, so scrolling up pushes the range/legend off the top and the
        // chart uses the whole viewport. Wide/landscape just fills the height.
        child: portrait
            ? LayoutBuilder(builder: (context, c) {
                return SingleChildScrollView(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ...controls,
                        SizedBox(height: c.maxHeight, child: content()),
                      ]),
                );
              })
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [...controls, Expanded(child: content())]),
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

enum _Anchor { left, center, right }

class _MultiLinePainter extends CustomPainter {
  _MultiLinePainter(this.series, this.cs, this.rangeLabel, this.cursorFrac);
  final List<_Series> series;
  final ColorScheme cs;
  final String rangeLabel;
  final double? cursorFrac;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width - _padL - _padR;
    final ht = size.height - _padT - _padB;

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

    double sx(DateTime t) => _padL + (t.millisecondsSinceEpoch - t0) / tSpan * w;
    double sy(double v) => _padT + (yHi - v) / (yHi - yLo) * ht;

    final grid = Paint()
      ..color = cs.outlineVariant.withValues(alpha: 0.4)
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final v = yLo + (yHi - yLo) * i / 4;
      final y = sy(v);
      canvas.drawLine(Offset(_padL, y), Offset(_padL + w, y),
          v.abs() < 1e-9 ? (grid..color = cs.outlineVariant) : grid);
      _txt(canvas, '${(v * 100).round()}%', Offset(_padL - 6, y - 6));
    }

    // ---- x-axis: evenly spaced date ticks with faint gridlines, so the line
    // can be read against actual dates (not just an unlabeled span).
    final xGrid = Paint()
      ..color = cs.outlineVariant.withValues(alpha: 0.25)
      ..strokeWidth = 1;
    const xTicks = 3;
    for (var i = 0; i <= xTicks; i++) {
      final frac = i / xTicks;
      final x = _padL + frac * w;
      final dt = DateTime.fromMillisecondsSinceEpoch((t0 + frac * tSpan).round());
      if (i > 0 && i < xTicks) {
        canvas.drawLine(Offset(x, _padT), Offset(x, _padT + ht), xGrid);
      }
      _txt(canvas, date(dt), Offset(x, _padT + ht + 5),
          anchor: i == 0 ? _Anchor.left : (i == xTicks ? _Anchor.right : _Anchor.center));
    }

    // Area fills first (under every line) — the portfolio's filled band.
    final plot = Rect.fromLTWH(_padL, _padT, w, ht);
    for (final s in series) {
      if (!s.area || s.pts.isEmpty) continue;
      final fill = Path()..moveTo(sx(s.pts.first.$1), _padT + ht);
      for (final p in s.pts) {
        fill.lineTo(sx(p.$1), sy(p.$2));
      }
      fill
        ..lineTo(sx(s.pts.last.$1), _padT + ht)
        ..close();
      final shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [s.color.withValues(alpha: 0.32), s.color.withValues(alpha: 0.0)],
      ).createShader(plot);
      canvas.save();
      canvas.clipRect(plot);
      canvas.drawPath(fill, Paint()..shader = shader);
      canvas.restore();
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
            ..strokeWidth = s.area ? 3 : 2
            ..style = PaintingStyle.stroke);
    }

    // ---- crosshair: vertical line + a dot & value label per line ----
    if (cursorFrac != null && series.isNotEmpty) {
      final cx = _padL + cursorFrac! * w;
      canvas.drawLine(Offset(cx, _padT), Offset(cx, _padT + ht),
          Paint()..color = cs.onSurface.withValues(alpha: 0.5)..strokeWidth = 1);
      final cursorMs = (t0 + cursorFrac! * tSpan).round();
      DateTime? at;
      // Right-align labels if the cursor is past mid-chart (avoid clipping).
      final left = cursorFrac! > 0.6;
      final marks = <({Color color, double dotY, String text})>[];
      for (final s in series) {
        // nearest point in time
        (DateTime, double)? best;
        var bestD = double.infinity;
        for (final p in s.pts) {
          final d = (p.$1.millisecondsSinceEpoch - cursorMs).abs().toDouble();
          if (d < bestD) {
            bestD = d;
            best = p;
          }
        }
        if (best == null) continue;
        at ??= best.$1;
        final o = Offset(sx(best.$1), sy(best.$2));
        canvas.drawCircle(o, 3.5, Paint()..color = Colors.white);
        canvas.drawCircle(o, 3.5,
            Paint()..color = s.color..strokeWidth = 2..style = PaintingStyle.stroke);
        marks.add((color: s.color, dotY: o.dy, text: pctSigned(best.$2)));
      }
      // Spread overlapping labels apart (flat/close lines cluster otherwise);
      // filled chips (line color bg, white text) keep values readable.
      marks.sort((a, b) => a.dotY.compareTo(b.dotY));
      const gap = 16.0;
      var prevY = double.negativeInfinity;
      for (final m in marks) {
        var y = m.dotY < prevY + gap ? prevY + gap : m.dotY;
        y = y.clamp(_padT + 9.0, _padT + ht - 2.0);
        prevY = y;
        _chip(canvas, m.text, Offset(cx + (left ? -8 : 8), y),
            bg: m.color, fg: Colors.white, anchor: left ? _Anchor.right : _Anchor.left);
      }
      if (at != null) {
        _chip(canvas, date(at), Offset(cx, _padT + ht + 3),
            bg: cs.surfaceContainerHighest, fg: cs.onSurface, anchor: _Anchor.center);
      }
    }
  }

  void _txt(Canvas canvas, String s, Offset at,
      {Color? color, _Anchor anchor = _Anchor.right}) {
    final tp = TextPainter(
      text: TextSpan(
          text: s,
          style: TextStyle(color: color ?? cs.onSurfaceVariant, fontSize: 10)),
      textDirection: TextDirection.ltr,
    )..layout();
    var dx = at.dx;
    if (anchor == _Anchor.right) dx -= tp.width;
    if (anchor == _Anchor.center) dx -= tp.width / 2;
    tp.paint(canvas, Offset(dx, at.dy));
  }

  /// A small filled, rounded label (so crosshair values don't blend into the
  /// lines). [at] is the anchor point; vertically centered on it.
  void _chip(Canvas canvas, String s, Offset at,
      {required Color bg, required Color fg, _Anchor anchor = _Anchor.left}) {
    final tp = TextPainter(
      text: TextSpan(
          text: s,
          style: TextStyle(color: fg, fontSize: 10, fontWeight: FontWeight.w700)),
      textDirection: TextDirection.ltr,
    )..layout();
    const padH = 4.0, padV = 2.0;
    final boxW = tp.width + padH * 2, boxH = tp.height + padV * 2;
    var x = at.dx;
    if (anchor == _Anchor.right) x -= boxW;
    if (anchor == _Anchor.center) x -= boxW / 2;
    final rect = Rect.fromLTWH(x, at.dy - boxH / 2, boxW, boxH);
    canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)), Paint()..color = bg);
    tp.paint(canvas, Offset(x + padH, rect.top + padV));
  }

  @override
  bool shouldRepaint(covariant _MultiLinePainter old) =>
      old.series != series ||
      old.rangeLabel != rangeLabel ||
      old.cursorFrac != cursorFrac;
}
