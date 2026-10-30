import 'package:flutter/material.dart';

/// Holds the analytics screen's content — the view toggle, the month navigator, the chart and the
/// legend — in a centred column of at most [maxWidth], so a wide window does not pull a legend
/// row's category and its figures to opposite edges of the screen.
///
/// The cap is wider than a list's: a chart wants room, a row of text does not. When the app
/// bounds every screen in the shell (jlogicsoftware/prudent#195) this folds into that constant.
class AnalyticsColumn extends StatelessWidget {
  const AnalyticsColumn({super.key, required this.child});

  /// The widest the analytics content grows, in logical pixels.
  static const double maxWidth = 720;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
