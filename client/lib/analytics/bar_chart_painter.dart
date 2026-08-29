import 'package:flutter/material.dart';

/// One bar: a pre-formatted label (the caller renders month names from its own locale — the
/// server sends only "yyyy-MM", proto/prudent/v1/analytics.proto) and a value.
@immutable
class ChartBar {
  const ChartBar({required this.label, required this.value});

  final String label;
  final double value;
}

/// A trailing-window bar chart — spend by month — over [bars]. No charting dependency, matching
/// [DonutChartPainter]'s reasoning.
///
/// [bars] is expected to be gap-filled by the caller to one entry per requested period (an
/// omitted period from the server means zero spend, not "no bar"), so an EMPTY list here means
/// zero PERIODS were requested, not zero spend — the caller's empty state covers "the account has
/// no periods to show", and a chart of all-zero bars is a real, different state this class paints
/// as flat bars rather than nothing.
class BarChartPainter extends CustomPainter {
  const BarChartPainter({required this.bars, required this.barColor, required this.labelStyle});

  final List<ChartBar> bars;
  final Color barColor;
  final TextStyle labelStyle;

  static const double _labelHeight = 20;
  static const double _barGap = 4;

  @override
  void paint(Canvas canvas, Size size) {
    if (bars.isEmpty) return;
    final chartHeight = size.height - _labelHeight;
    final maxValue = bars.fold<double>(0, (m, b) => b.value > m ? b.value : m);
    final barWidth = (size.width - _barGap * (bars.length - 1)) / bars.length;

    for (var i = 0; i < bars.length; i++) {
      final bar = bars[i];
      // maxValue == 0 means every bucket is genuinely zero (no expenses at all in the window):
      // every bar is painted as a minimal sliver rather than divide-by-zero producing a full-height
      // bar that would misrepresent "nothing was spent" as "everything was spent".
      final fraction = maxValue <= 0 ? 0.0 : bar.value / maxValue;
      final barHeight = (chartHeight * fraction).clamp(bar.value > 0 ? 2.0 : 0.0, chartHeight);
      final left = i * (barWidth + _barGap);
      final rect = Rect.fromLTWH(left, chartHeight - barHeight, barWidth, barHeight);
      canvas.drawRRect(
        RRect.fromRectAndCorners(rect, topLeft: const Radius.circular(3), topRight: const Radius.circular(3)),
        Paint()..color = barColor,
      );

      final painter = TextPainter(
        text: TextSpan(text: bar.label, style: labelStyle),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout(maxWidth: barWidth + _barGap);
      painter.paint(
        canvas,
        Offset(left + (barWidth - painter.width) / 2, size.height - _labelHeight + 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant BarChartPainter oldDelegate) =>
      oldDelegate.bars != bars || oldDelegate.barColor != barColor;
}
