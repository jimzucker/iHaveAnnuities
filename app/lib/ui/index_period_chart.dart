// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: Apache-2.0
// The underlying index over the contract's current period (since the last
// reset), with the strike, cap, and floor/buffer levels drawn as reference
// lines and the no-loss / capped zones shaded. Falls back to the structural
// payoff diagram when history isn't available (or for income notes).

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../core/models.dart';
import '../data/index_history.dart';
import 'format.dart';
import 'payoff_chart.dart';

// Plot padding — shared so the cursor gesture and the painter agree on geometry.
const _padL = 58.0, _padR = 12.0, _padT = 14.0, _padB = 22.0;

class IndexPeriodChart extends StatefulWidget {
  const IndexPeriodChart({super.key, required this.holding, this.base = '', this.client});

  final Holding holding;
  final String base;
  final http.Client? client;

  @override
  State<IndexPeriodChart> createState() => _IndexPeriodChartState();
}

class _IndexPeriodChartState extends State<IndexPeriodChart> {
  IndexHistory? _hist;
  bool _failed = false;
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
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.holding;
    final cs = Theme.of(context).colorScheme;
    if (!_failed && _hist == null) {
      return const SizedBox(height: 250, child: Center(child: CircularProgressIndicator()));
    }
    final series = _hist?.series(h.baseIndex, HistoryRange.max) ?? const [];
    final pts = series.where((p) => !p.$1.isBefore(h.lastReset)).toList();

    // Income notes have no cap/floor on the index in this sense; and we need at
    // least a short series. Fall back to the structural payoff diagram.
    if (_failed || h.isIncomeNote || pts.length < 2) {
      return _captioned(
        cs,
        PayoffChart(holding: h),
        'Return at reset vs. the index move. Today the index is '
            '${pctSigned(h.indexGain)} → you would receive ${pctSigned(h.projGain)}.',
      );
    }

    final lastLvl = pts.last.$2;
    final caption = 'Your index (${h.index}) since the last reset on '
        '${date(h.lastReset)}. Green = no-loss zone'
        '${h.cap == null ? '' : ', amber = above the ${capLabel(h.cap)} cap'}. '
        'Now ${level(lastLvl)} (${pctSigned(lastLvl / h.strike - 1)} from strike).';

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 16, runSpacing: 4, children: [
        _leg(cs.primary, h.index),
        _leg(cs.outline, 'strike'),
        if (h.cap != null) _leg(capAmber, 'cap'),
        _leg(gainGreen, 'no loss'),
        if (h.floor < 0) _leg(lossRed, 'loss'),
      ]),
      const SizedBox(height: 8),
      SizedBox(
        height: 250,
        child: LayoutBuilder(builder: (context, box) {
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
                painter: _IndexPeriodPainter(h, pts, cs, _cursorFrac),
                child: const SizedBox.expand(),
              ),
            ),
          );
        }),
      ),
      const SizedBox(height: 8),
      Text(caption,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: cs.onSurfaceVariant, height: 1.35)),
    ]);
  }

  Widget _captioned(ColorScheme cs, Widget chart, String caption) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        chart,
        const SizedBox(height: 8),
        Text(caption,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: cs.onSurfaceVariant, height: 1.35)),
      ]);

  Widget _leg(Color c, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 16, height: 3, color: c),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11)),
      ]);
}

class _IndexPeriodPainter extends CustomPainter {
  _IndexPeriodPainter(this.h, this.pts, this.cs, this.cursorFrac);
  final Holding h;
  final List<(DateTime, double)> pts;
  final ColorScheme cs;
  final double? cursorFrac; // 0..1 across the plot; null when not hovering

  @override
  void paint(Canvas canvas, Size size) {
    const padL = _padL, padR = _padR, padT = _padT, padB = _padB;
    final w = size.width - padL - padR;
    final ht = size.height - padT - padB;

    final strike = h.strike;
    final capLvl = h.cap == null ? null : strike * (1 + h.cap!);
    final floorLvl = h.floor == 0 ? null : strike * (1 + h.floor);

    var lo = pts.first.$2, hi = pts.first.$2;
    for (final p in pts) {
      lo = lo < p.$2 ? lo : p.$2;
      hi = hi > p.$2 ? hi : p.$2;
    }
    lo = [lo, strike, floorLvl ?? lo].reduce((a, b) => a < b ? a : b);
    hi = [hi, strike, capLvl ?? hi].reduce((a, b) => a > b ? a : b);
    final span = (hi - lo) == 0 ? (hi == 0 ? 1.0 : hi.abs() * 0.02) : (hi - lo);
    final yLo = lo - span * 0.08, yHi = hi + span * 0.08;
    final t0 = pts.first.$1.millisecondsSinceEpoch.toDouble();
    final t1 = pts.last.$1.millisecondsSinceEpoch.toDouble();
    final tSpan = (t1 - t0) == 0 ? 1.0 : (t1 - t0);

    double sx(DateTime t) => padL + (t.millisecondsSinceEpoch - t0) / tSpan * w;
    double sy(double v) => padT + (yHi - v) / (yHi - yLo) * ht;

    // ---- shaded zones (by index level) ----
    void band(double a, double b, Color c) {
      final top = sy(b).clamp(padT, padT + ht), bot = sy(a).clamp(padT, padT + ht);
      if ((bot - top).abs() < 1) return;
      canvas.drawRect(Rect.fromLTRB(padL, top, padL + w, bot),
          Paint()..color = c.withValues(alpha: 0.13));
    }

    if (capLvl != null) band(capLvl, yHi, capAmber); // capped
    band(floorLvl ?? yLo, strike, gainGreen); // no-loss zone
    if (floorLvl != null) band(yLo, floorLvl, lossRed); // loss zone

    // y gridlines + level labels
    final grid = Paint()
      ..color = cs.outlineVariant.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final v = yLo + (yHi - yLo) * i / 4;
      final y = sy(v);
      canvas.drawLine(Offset(padL, y), Offset(padL + w, y), grid);
      _txt(canvas, level(v), Offset(padL - 6, y - 6), anchor: _A.right);
    }

    // reference lines (dashed)
    void refLine(double v, Color c, String label) {
      final y = sy(v);
      _dashed(canvas, Offset(padL, y), Offset(padL + w, y),
          Paint()..color = c.withValues(alpha: 0.85)..strokeWidth = 1.2);
      _txt(canvas, label, Offset(padL + w - 2, y - 12), anchor: _A.right, color: c);
    }

    refLine(strike, cs.outline,
        h.floor == 0 ? 'strike · 0% floor' : 'strike');
    if (capLvl != null) refLine(capLvl, capAmber, 'cap ${pct(h.cap!)}');
    if (floorLvl != null) refLine(floorLvl, lossRed, 'floor ${pct(h.floor)}');

    // ---- index line ----
    final path = Path();
    for (var i = 0; i < pts.length; i++) {
      final o = Offset(sx(pts[i].$1), sy(pts[i].$2));
      i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = cs.primary
          ..strokeWidth = 2.2
          ..style = PaintingStyle.stroke);

    // current marker
    final last = Offset(sx(pts.last.$1), sy(pts.last.$2));
    canvas.drawCircle(last, 4, Paint()..color = Colors.white);
    canvas.drawCircle(last, 4,
        Paint()..color = cs.primary..strokeWidth = 2..style = PaintingStyle.stroke);

    // ---- x-axis: evenly spaced date ticks with faint gridlines ----
    final tick = Paint()
      ..color = cs.outlineVariant.withValues(alpha: 0.25)
      ..strokeWidth = 1;
    const ticks = 4;
    for (var i = 0; i <= ticks; i++) {
      final frac = i / ticks;
      final x = padL + frac * w;
      final dt = DateTime.fromMillisecondsSinceEpoch((t0 + frac * tSpan).round());
      if (i > 0 && i < ticks) {
        canvas.drawLine(Offset(x, padT), Offset(x, padT + ht), tick);
      }
      _txt(canvas, date(dt), Offset(x, padT + ht + 5),
          anchor: i == 0 ? _A.left : (i == ticks ? _A.right : _A.center));
    }

    // ---- crosshair cursor (hover / touch) ----
    if (cursorFrac != null && pts.length >= 2) {
      final cx = padL + cursorFrac! * w;
      final targetMs = t0 + cursorFrac! * tSpan;
      // nearest sample to the cursor
      var best = pts.first;
      var bestD = double.infinity;
      for (final p in pts) {
        final d = (p.$1.millisecondsSinceEpoch - targetMs).abs();
        if (d < bestD) {
          bestD = d;
          best = p;
        }
      }
      // vertical crosshair line
      canvas.drawLine(Offset(cx, padT), Offset(cx, padT + ht),
          Paint()..color = cs.onSurface.withValues(alpha: 0.45)..strokeWidth = 1);
      // dot on the index line
      final o = Offset(sx(best.$1), sy(best.$2));
      canvas.drawCircle(o, 4, Paint()..color = Colors.white);
      canvas.drawCircle(o, 4,
          Paint()..color = cs.primary..strokeWidth = 2..style = PaintingStyle.stroke);
      // value chip: index level + move from strike
      final move = strike == 0 ? 0.0 : best.$2 / strike - 1;
      _chip(canvas, '${level(best.$2)}  (${pctSigned(move)})',
          Offset(cx, padT + 2), cs.primary, Colors.white,
          flip: cursorFrac! > 0.6, plotR: padL + w);
      // date chip on the x-axis
      _chip(canvas, date(best.$1), Offset(cx, padT + ht + 4),
          cs.onSurface, cs.surface,
          flip: cursorFrac! > 0.6, plotR: padL + w);
    }
  }

  /// A small filled label anchored at [at] (the cursor x), flipping to the left
  /// of the cursor near the right edge so it never clips.
  void _chip(Canvas canvas, String s, Offset at, Color bg, Color fg,
      {bool flip = false, double plotR = 0}) {
    final tp = TextPainter(
      text: TextSpan(
          text: s,
          style: TextStyle(color: fg, fontSize: 10, fontWeight: FontWeight.w600)),
      textDirection: TextDirection.ltr,
    )..layout();
    const padX = 5.0, padY = 2.0;
    final boxW = tp.width + padX * 2, boxH = tp.height + padY * 2;
    var left = flip ? at.dx - 8 - boxW : at.dx + 8;
    left = left.clamp(_padL, (plotR - boxW).clamp(_padL, plotR));
    final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, at.dy, boxW, boxH), const Radius.circular(4));
    canvas.drawRRect(rect, Paint()..color = bg);
    tp.paint(canvas, Offset(left + padX, at.dy + padY));
  }

  void _txt(Canvas canvas, String s, Offset at, {Color? color, _A anchor = _A.left}) {
    final tp = TextPainter(
      text: TextSpan(
          text: s,
          style: TextStyle(
              color: color ?? cs.onSurfaceVariant,
              fontSize: 10,
              fontWeight: color == null ? FontWeight.normal : FontWeight.w600)),
      textDirection: TextDirection.ltr,
    )..layout();
    var dx = at.dx;
    if (anchor == _A.right) dx -= tp.width;
    if (anchor == _A.center) dx -= tp.width / 2;
    tp.paint(canvas, Offset(dx, at.dy));
  }

  void _dashed(Canvas canvas, Offset a, Offset b, Paint p) {
    const dash = 5.0, gap = 4.0;
    final total = (b - a).distance;
    if (total == 0) return;
    final dir = (b - a) / total;
    var d = 0.0;
    while (d < total) {
      canvas.drawLine(a + dir * d, a + dir * (d + dash).clamp(0, total).toDouble(), p);
      d += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _IndexPeriodPainter old) =>
      old.pts != pts || old.h != h || old.cursorFrac != cursorFrac;
}

enum _A { left, center, right }
