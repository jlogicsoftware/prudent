import 'package:flutter/material.dart';

import '../account/account_screen.dart';
import '../chart/chart_screen.dart';
import '../src/l10n/generated/prudent_localizations.dart';

/// Stub — real content is new product work for Phase 4 (docs/prudent-migration-plan.md), not this
/// one.
class OverviewScreen extends StatelessWidget {
  const OverviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = PrudentLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.appTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.pie_chart_outline),
            onPressed:
                () => Navigator.of(context).push(MaterialPageRoute(builder: (ctx) => const ChartScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.list),
            onPressed:
                () => Navigator.of(context).push(MaterialPageRoute(builder: (ctx) => const AccountScreen())),
          ),
        ],
      ),
      body: Center(
        child: Column(
          children: [
            Text(t.overviewChartStub, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            Text(t.overviewAccountsStub, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
