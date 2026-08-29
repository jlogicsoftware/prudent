import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../record/record_item.dart';
import '../generated/prudent/v1/categories.pb.dart';
import '../l10n/generated/prudent_localizations.dart';
import '../providers.dart';

/// Every record in one category — made reachable in Phase 4
/// (docs/prudent-migration-plan.md); it had a `routeName` `main.dart` never wired up.
class CategoryRecords extends ConsumerWidget {
  final Category category;

  const CategoryRecords({super.key, required this.category});
  static const routeName = '/category-records';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = PrudentLocalizations.of(context);
    final recordsAsync = ref.watch(recordsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(category.title)),
      body: recordsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text(t.recordsLoadError(error.toString()))),
        data: (records) {
          final inCategory = records.where((r) => r.categoryId == category.id).toList();
          if (inCategory.isEmpty) {
            return Center(child: Text(t.categoryRecordsEmpty));
          }
          return ListView(
            children: [for (final record in inCategory) RecordItem(record, category: category)],
          );
        },
      ),
    );
  }
}
