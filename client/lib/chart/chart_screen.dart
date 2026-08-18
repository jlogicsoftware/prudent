import 'package:flutter/material.dart';

import '../src/l10n/generated/prudent_localizations.dart';

/// Stub — real content is new product work for Phase 4 (docs/prudent-migration-plan.md), not this
/// one.
class ChartScreen extends StatelessWidget {
  const ChartScreen({super.key});

  static const routName = '/chart';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: Center(child: Text(PrudentLocalizations.of(context).chartStub)),
    );
  }
}
