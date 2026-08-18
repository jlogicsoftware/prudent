import 'package:flutter/material.dart';

import '../src/generated/prudent/v1/categories.pb.dart';
import '../src/l10n/generated/prudent_localizations.dart';

/// Stub — made reachable in Phase 4 (docs/prudent-migration-plan.md), not this one.
class CategoryRecords extends StatelessWidget {
  final Category category;

  const CategoryRecords({super.key, required this.category});
  static const routeName = '/category-records';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(category.title)),
      body: Center(child: Text(PrudentLocalizations.of(context).categoryRecordsStub)),
    );
  }
}
