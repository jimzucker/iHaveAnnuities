// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: Apache-2.0
// Payoff diagram: payoff return vs. index move, with axis ticks/gridlines, the
// 1:1 index reference, cap and barrier/buffer reference lines, and a labeled
// marker at the current index gain.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/payoff.dart';
import 'format.dart';

class PayoffChart extends StatelessWidget {
  const PayoffChart({super.key, required this.holding, this.range = 0.40});

  final Holding holding;
  final double range;

  @override
  Widget build(BuildContext context) {
    final h = holding;
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Return chart. Index move ${pctSigned(h.indexGain)} maps to a '
          'projected return of ${pctSigned(h.projGain)}. Protection: '
          '${h.protectionType}, cap ${capLabel(h.cap)}.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6, left: 4),
          child: Wrap(spacing: 16, runSpacing: 4, children: [
            _legend(cs.primary, 'payoff', solid: true),
            _legend(cs.outline, 'index (1:1)', solid: false),
            if (h.cap != null) _legend(capAmber, 'cap', solid: false),
            if (h.floorType == FloorType.none)
              _legend(lossRed, 'full loss', solid: false)
            else if (h.floor < 0)
              _legend(h.floorType == FloorType.soft ? capAmber : gainGreen,
                  h.floorType == FloorType.soft ? 'barrier' : 'buffer',
                  solid: false),
          ]),
        ),
        SizedBox(
          height: 300,
          child: CustomPaint(
            painter: _PayoffPainter(h, range, cs),
            child: const SizedBox.expand(),
          ),
        ),
      ]),
    );
  }

  Widget _legend(Color c, String label, {required bool solid}) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 22,
            height: 4,
            decoration: BoxDecoration(
                color: solid ? c : c.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      ]);
}

class _PayoffPainter extends CustomPainter {
  _PayoffPainter(this.h, this.range, this.cs);
  final Holding h;
  final double range;
  final ColorScheme cs;

  double _payoff(double idx) => h.isIncomeNote
      ? h.couponRate
      : payoffReturn(idx,
          cap: h.cap,
          participation: h.participation,
          floor: h.floor,
          floorType: h.floorType);

  @override
  void paint(Canvas canvas, Size size) {
    const padL = 64.0, padR = 18.0, padT = 16.0, padB = 38.0;
    final w = size.width - padL - padR;
    final ht = size.height - padT - padB;
    final idxLo = -range, idxHi = range;

    // Tighten the y-range to the payoff band (plus the cap) so the line fills
    // the chart instead of floating in empty space.
    double pmin = 0, pmax = 0;
    for (var i = 0; i <= 160; i++) {
      final p = _payoff(idxLo + (idxHi - idxLo) * i / 160);
      pmin = math.min(pmin, p);
      pmax = math.max(pmax, p);
    }
    if (h.cap != null) pmax = math.max(pmax, h.cap!);
    final span = math.max(pmax - pmin, 0.05);
    final yMax = pmax + span * 0.12;
    final yMin = pmin - span * 0.12;

    double sx(double idx) => padL + (idx - idxLo) / (idxHi - idxLo) * w;
    double sy(double v) => padT + (yMax - v) / (yMax - yMin) * ht;

    final grid = Paint()
      ..color = cs.outlineVariant.withValues(alpha: 0.55)
      ..strokeWidth = 1;
    final axis = Paint()
      ..color = cs.outlineVariant
      ..strokeWidth = 1;

    // x gridlines + ticks every 20%
    for (var t = -range; t <= range + 1e-9; t += 0.20) {
      final x = sx(t);
      canvas.drawLine(Offset(x, padT), Offset(x, padT + ht), t.abs() < 1e-9 ? axis : grid);
      _label(canvas, '${(t * 100).round()}%', Offset(x, padT + ht + 4), center: true);
    }
    // y gridlines + ticks (nice step)
    final yStep = _niceStep((yMax - yMin) / 5);
    for (var t = (yMin / yStep).ceilToDouble() * yStep; t <= yMax + 1e-9; t += yStep) {
      final y = sy(t);
      canvas.drawLine(Offset(padL, y), Offset(padL + w, y), t.abs() < 1e-9 ? axis : grid);
      _label(canvas, '${(t * 100).round()}%', Offset(padL - 6, y - 6), right: true);
    }

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(padL, padT, w, ht));

    // Shaded zones with labels — the chart's "message" at a glance:
    // green = no loss, red = loss/barrier, amber = capped.
    if (!h.isIncomeNote) {
      void band(double xa, double xb, Color c, String label) {
        final l = sx(xa).clamp(padL, padL + w);
        final r = sx(xb).clamp(padL, padL + w);
        if (r - l < 6) return;
        canvas.drawRect(Rect.fromLTRB(l, padT, r, padT + ht),
            Paint()..color = c.withValues(alpha: 0.16));
        _label(canvas, label, Offset((l + r) / 2, padT + 1), center: true);
      }

      if (h.floorType == FloorType.none) {
        band(idxLo, 0, lossRed, 'full loss'); // no protection — 1:1 downside
      } else {
        band(h.floor < 0 ? h.floor : idxLo, 0, gainGreen, 'no loss');
        if (h.floor < 0) {
          band(idxLo, h.floor, lossRed,
              h.floorType == FloorType.soft ? 'barrier' : 'buffer');
        }
      }
      if (h.cap != null) {
        band((h.cap! / h.participation).clamp(0.0, idxHi).toDouble(), idxHi,
            capAmber, 'capped');
      }
    }

    // 1:1 index reference
    canvas.drawLine(Offset(sx(idxLo), sy(idxLo)), Offset(sx(idxHi), sy(idxHi)),
        Paint()..color = cs.outline.withValues(alpha: 0.6)..strokeWidth = 1.6);

    // cap ceiling (dashed amber)
    if (h.cap != null) {
      _dashed(canvas, Offset(padL, sy(h.cap!)), Offset(padL + w, sy(h.cap!)),
          Paint()..color = capAmber.withValues(alpha: 0.85)..strokeWidth = 1.6);
    }
    // barrier / buffer knee (dashed vertical at index = floor)
    if (h.floor < 0 && h.floor > idxLo) {
      final c = h.floorType == FloorType.soft ? capAmber : gainGreen;
      _dashed(canvas, Offset(sx(h.floor), padT), Offset(sx(h.floor), padT + ht),
          Paint()..color = c.withValues(alpha: 0.75)..strokeWidth = 1.6);
    }

    // payoff curve
    final path = Path();
    for (var i = 0; i <= 160; i++) {
      final idx = idxLo + (idxHi - idxLo) * i / 160;
      final p = Offset(sx(idx), sy(_payoff(idx)));
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = cs.primary
          ..strokeWidth = 3.0
          ..style = PaintingStyle.stroke);

    // current position
    final gi = h.indexGain.clamp(idxLo, idxHi);
    final pt = Offset(sx(gi), sy(_payoff(h.indexGain).clamp(yMin, yMax)));
    canvas.drawCircle(pt, 5.5, Paint()..color = cs.secondary);
    canvas.restore();

    // marker label (outside the clip so it isn't cut off)
    _label(canvas, '${pctSigned(h.indexGain)} → ${pctSigned(h.projGain)}',
        Offset((pt.dx + 10).clamp(padL, padL + w - 170), pt.dy - 20), accent: true);

    _label(canvas, 'index →', Offset(padL + w - 4, padT + ht + 4), right: true);
  }

  void _label(Canvas canvas, String t, Offset at,
      {bool center = false, bool right = false, bool accent = false}) {
    final tp = TextPainter(
      text: TextSpan(
          text: t,
          style: TextStyle(
              // The accent (marker) label sits on a filled chip, so use the
              // high-contrast tooltip foreground; plain labels use onSurface.
              color: accent ? cs.onInverseSurface : cs.onSurface,
              fontWeight: accent ? FontWeight.w700 : FontWeight.w600,
              fontSize: accent ? 15 : 15)),
      textDirection: TextDirection.ltr,
    )..layout();
    var dx = at.dx;
    if (center) dx -= tp.width / 2;
    if (right) dx -= tp.width;
    // Solid chip behind the marker label so the payoff line doesn't cut through it.
    if (accent) {
      const px = 7.0, py = 4.0;
      final rect = Rect.fromLTWH(dx - px, at.dy - py, tp.width + px * 2, tp.height + py * 2);
      canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(6)),
          Paint()..color = cs.inverseSurface);
    }
    tp.paint(canvas, Offset(dx, at.dy));
  }

  void _dashed(Canvas canvas, Offset a, Offset b, Paint p) {
    const dash = 5.0, gap = 4.0;
    final total = (b - a).distance;
    if (total == 0) return;
    final dir = (b - a) / total;
    var d = 0.0;
    while (d < total) {
      canvas.drawLine(a + dir * d, a + dir * math.min(d + dash, total), p);
      d += dash + gap;
    }
  }

  double _niceStep(double raw) {
    if (raw <= 0) return 0.05;
    final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    final norm = raw / mag;
    final nice = norm < 1.5 ? 1.0 : (norm < 3 ? 2.0 : (norm < 7 ? 5.0 : 10.0));
    return nice * mag;
  }

  @override
  bool shouldRepaint(covariant _PayoffPainter old) =>
      old.h != h || old.range != range;
}
