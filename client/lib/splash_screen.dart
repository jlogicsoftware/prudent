import 'package:flutter/material.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

/// Shown while the stored identity session is still being read.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const ZenPageScaffold(body: Center(child: ZenProgressIndicator()));
}
