import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zen_core/zen_core.dart';

import '../src/generated/prudent/v1/categories.pb.dart';
import '../src/l10n/generated/prudent_localizations.dart';
import '../src/providers.dart';
import '../widgets/popup/popup.dart';
import 'category_grid_items.dart';
import 'new_category.dart';

class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  static const routeName = '/categories';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final t = PrudentLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(t.categoriesTitle),
        actions: [
          Popup(
            popupLeading: const Icon(Icons.add),
            popupBody: NewCategory(
              onSave:
                  ({
                    required title,
                    required iconKey,
                    required description,
                    required colorArgb,
                  }) => ref
                      .read(categoriesProvider.notifier)
                      .addCategory(
                        CreateCategoryRequest(
                          title: title,
                          iconKey: iconKey,
                          description: description,
                          colorArgb: colorArgb,
                        ),
                      ),
            ),
          ),
        ],
      ),
      body: categoriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text(t.categoriesLoadError(error.toString()))),
        data: (categories) {
          if (categories.isEmpty) {
            return Center(child: Text(t.categoriesEmpty));
          }
          return GridView(
            padding: const EdgeInsets.all(20),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: zenIsDesktop ? 3 : 2,
              mainAxisExtent: zenIsDesktop ? 200 : 150,
              childAspectRatio: zenIsDesktop ? 2 : 1.5,
              crossAxisSpacing: 20,
              mainAxisSpacing: 20,
            ),
            children: [
              for (final category in categories)
                Popup(
                  popupLeading: CategoryGridItem(category: category),
                  popupBody: NewCategory(
                    initialCategory: category,
                    onSave:
                        ({
                          required title,
                          required iconKey,
                          required description,
                          required colorArgb,
                        }) => ref
                            .read(categoriesProvider.notifier)
                            .editCategory(
                              category.id,
                              UpdateCategoryRequest(
                                title: title,
                                iconKey: iconKey,
                                description: description,
                                colorArgb: colorArgb,
                              ),
                            ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
