import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../generated/prudent/v1/categories.pb.dart';
import '../l10n/generated/prudent_localizations.dart';
import '../providers.dart';
import '../popup.dart';
import 'category_grid_items.dart';
import 'category_records.dart';
import 'new_category.dart';

class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  static const routeName = '/categories';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final t = PrudentLocalizations.of(context);

    return ZenPageScaffold(
      title: t.categoriesTitle,
      actions: [
        Popup(
          icon: Icons.add,
          label: t.addCategoryTooltip,
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
      body: categoriesAsync.when(
        loading: () => const Center(child: ZenProgressIndicator()),
        error:
            (error, _) =>
                Center(child: Text(t.categoriesLoadError(error.toString()))),
        data: (categories) {
          if (categories.isEmpty) {
            return Center(child: Text(t.categoriesEmpty));
          }
          // The density follows the width this grid is given, not the platform: a wide browser
          // window is still `web` and a desktop window can be dragged narrow, and only the
          // constraints know either. zenNarrowWidth is the framework's own breakpoint (the nav
          // shell switches on it), so the grid and the shell change layout at the same width.
          return LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < zenNarrowWidth;
              return GridView(
                padding: const EdgeInsets.all(20),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: narrow ? 2 : 3,
                  mainAxisExtent: narrow ? 150 : 200,
                  crossAxisSpacing: 20,
                  mainAxisSpacing: 20,
                ),
                children: [
                  for (final category in categories)
                    Stack(
                      children: [
                        // A TAP OPENS THE CATEGORY'S RECORDS, not the edit form: CategoryRecords was
                        // unreachable before this phase (docs/prudent-migration-plan.md), and giving
                        // it the tile's main gesture is what makes it reachable rather than a second
                        // stub nobody can get to.
                        InkWell(
                          borderRadius: BorderRadius.circular(15),
                          onTap:
                              () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder:
                                      (ctx) =>
                                          CategoryRecords(category: category),
                                ),
                              ),
                          child: CategoryGridItem(category: category),
                        ),
                        Align(
                          alignment: Alignment.topRight,
                          child: Popup(
                            icon: Icons.edit_outlined,
                            label: t.editCategoryTooltip,
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
                        ),
                      ],
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
