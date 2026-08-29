import 'package:flutter/material.dart';

/// One slice of the donut: a pre-resolved colour and value, so the painter never has to know
/// about categories, currencies or anything else this is a chart FOR.
@immutable
class DonutSlice {
  const DonutSlice({required this.value, required this.color});

  final double value;
  final Color color;
}

/// A donut — a pie with a hole — over [slices]. No charting dependency: a `CustomPainter` adds
/// none, and the shape here (arcs summing to a full turn) does not earn one
/// (docs/prudent-migration-plan.md Phase 4, "a charting dependency or a CustomPainter").
///
/// Handles the shapes a pie chart actually breaks on: an EMPTY slice list paints nothing (the
/// caller renders the empty state instead of an empty circle that looks like a bug); ONE slice
/// paints a full ring rather than degenerating to a zero-length arc; MANY slices divide the turn
/// proportionally to [DonutSlice.value].
class DonutChartPainter extends CustomPainter {
  const DonutChartPainter({required this.slices, required this.trackColor});

  final List<DonutSlice> slices;

  /// Painted under every slice, so the ring reads as complete even before any slice is drawn.
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final strokeWidth = radius * 0.35;
    final rect = Rect.fromCircle(center: center, radius: radius - strokeWidth / 2);

    final track =
        Paint()
          ..color = trackColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth;
    canvas.drawArc(rect, 0, 6.283185307179586, false, track);

    final total = slices.fold<double>(0, (sum, slice) => sum + slice.value);
    if (total <= 0) return;

    var startAngle = -1.5707963267948966; // -pi/2, so the first slice starts at the top.
    for (final slice in slices) {
      final sweep = (slice.value / total) * 6.283185307179586;
      final paint =
          Paint()
            ..color = slice.color
            ..style = PaintingStyle.stroke
            ..strokeWidth = strokeWidth;
      // A single slice is swept to just under a full turn rather than exactly one: an arc swept
      // by exactly 2*pi degenerates to nothing under Canvas.drawArc, which would paint the SAME
      // "nothing" this class uses for the empty case above — visually indistinguishable from a
      // bug. 0.999 of a turn reads as a complete ring while remaining a real arc.
      final effectiveSweep = slices.length == 1 ? sweep * 0.999 : sweep;
      canvas.drawArc(rect, startAngle, effectiveSweep, false, paint);
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant DonutChartPainter oldDelegate) =>
      oldDelegate.slices != slices || oldDelegate.trackColor != trackColor;
}
