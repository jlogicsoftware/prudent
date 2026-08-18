import 'package:flutter/material.dart';

import '../src/l10n/generated/prudent_localizations.dart';

/// Stub — real content is new product work for Phase 4 (docs/prudent-migration-plan.md), not this
/// one.
class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = PrudentLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.analyticsTitle)),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(t.analyticsOverviewStub, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            Text(t.analyticsDetailStub, style: const TextStyle(fontSize: 16)),
          ],
        ),
      ),
    );
  }
}
