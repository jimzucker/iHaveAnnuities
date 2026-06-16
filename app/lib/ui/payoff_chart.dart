// Copyright 2026 Jim Zucker
// SPDX-License-Identifier: Apache-2.0
// Lightweight CustomPainter payoff diagram: payoff return vs. index move, with
// the unclamped index reference line and a marker at the current index gain.

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
    return Semantics(
      label: 'Payoff chart. Index move ${pctSigned(h.indexGain)} maps to a '
          'projected payoff of ${pctSigned(h.projGain)}. Protection: '
          '${h.protectionType}, cap ${capLabel(h.cap)}.',
      child: SizedBox(
        height: 240,
        child: CustomPaint(
          painter: _PayoffPainter(holding, range, Theme.of(context).colorScheme),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _PayoffPainter extends CustomPainter {
  _PayoffPainter(this.h, this.range, this.cs);
  final Holding h;
  final double range;
  final ColorScheme cs;

  double _payoff(double idx) => h.isIncomeNote
      ? h.couponProj
      : payoffReturn(idx,
          cap: h.cap,
          participation: h.participation,
          floor: h.floor,
          floorType: h.floorType);

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 28.0;
    final w = size.width - pad * 2;
    final ht = size.height - pad * 2;
    // Y range: clamp display to a sensible band around the payoff curve.
    final yMax = (h.cap == null ? range : (h.cap! + 0.05)).clamp(0.10, range + 0.10);
    final yMin = -(range);
    double sx(double idx) => pad + (idx + range) / (2 * range) * w;
    double sy(double v) => pad + (yMax - v) / (yMax - yMin) * ht;

    final axis = Paint()
      ..color = cs.outlineVariant
      ..strokeWidth = 1;
    // zero lines
    canvas.drawLine(Offset(sx(0), pad), Offset(sx(0), pad + ht), axis);
    canvas.drawLine(Offset(pad, sy(0)), Offset(pad + w, sy(0)), axis);

    // unclamped index reference (dashed-ish faint diagonal)
    final ref = Paint()
      ..color = cs.outline.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(sx(yMin), sy(yMin)), Offset(sx(yMax), sy(yMax)), ref);

    // payoff curve
    final curve = Paint()
      ..color = cs.primary
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    final path = Path();
    for (var i = 0; i <= 120; i++) {
      final idx = yMin + (yMax - yMin) * i / 120;
      final p = Offset(sx(idx), sy(_payoff(idx)));
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, curve);

    // current position marker
    final gain = h.indexGain.clamp(yMin, yMax);
    final dot = Paint()..color = cs.secondary;
    canvas.drawCircle(Offset(sx(gain), sy(_payoff(h.indexGain))), 4.5, dot);

    _label(canvas, 'index →', Offset(pad + w - 44, sy(0) + 4), cs);
    _label(canvas, 'payoff ↑', Offset(sx(0) + 4, pad - 2), cs);
  }

  void _label(Canvas canvas, String t, Offset at, ColorScheme cs) {
    final tp = TextPainter(
      text: TextSpan(
          text: t,
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 10)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(covariant _PayoffPainter old) =>
      old.h != h || old.range != range;
}
