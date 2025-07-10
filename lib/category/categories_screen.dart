import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:prudent/category/category.dart';
import 'package:prudent/category/category_grid_items.dart';
import 'package:prudent/category/category_provider.dart';
import 'package:prudent/category/new_category.dart';
import 'package:prudent/utils.dart';
import 'package:prudent/widgets/popup/popup.dart';

class CategoriesScreen extends ConsumerStatefulWidget {
  const CategoriesScreen({super.key});

  static const routeName = '/categories';

  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends ConsumerState<CategoriesScreen> {
  @override
  Widget build(BuildContext context) {
    late final List<Category> categories = ref.watch(categoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Categories'),
        actions: [
          Popup(
            popupLeading: const Icon(Icons.add),
            popupBody: NewCategory(
              onAddCategory:
                  (category) =>
                      ref.read(categoryProvider.notifier).addCategory(category),
            ),
          ),
        ],
      ),
      body: GridView(
        padding: const EdgeInsets.all(20),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: isMobile(context) ? 2 : 3,
          mainAxisExtent: isMobile(context) ? 150 : 200,
          childAspectRatio: isMobile(context) ? 1.5 : 2,
          crossAxisSpacing: 20,
          mainAxisSpacing: 20,
        ),
        children: [
          for (int index = 0; index < categories.length; index++)
            Popup(
              popupLeading: CategoryGridItem(category: categories[index]),
              popupBody: NewCategory(
                onAddCategory:
                    (category) => ref
                        .read(categoryProvider.notifier)
                        .editCategory(index, category),
                initialCategory: categories[index],
              ),
            ),
        ],
      ),
    );
  }
}
