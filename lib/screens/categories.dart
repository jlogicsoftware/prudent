import 'package:flutter/material.dart';

import 'package:prudent/category/category.dart';
import 'package:prudent/category/category_grid_items.dart';
import 'package:prudent/screens/category_records.dart';
import 'package:prudent/utils.dart';
import 'package:prudent/widgets/popup/popup.dart';

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  static const routeName = '/categories';

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  final List<Category> categories = Category.categories;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Categories'),
        actions: [
          Popup(
            icon: const Icon(Icons.add),
            popupContent: const Text('Add new category'),
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
          for (final category in categories)
            InkWell(
              splashColor: Theme.of(context).colorScheme.primary,
              highlightColor: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(15),
              onTap: () {
                // Navigator.pushNamed(
                //   context,
                //   CategoryRecords.routeName,
                //   arguments: <String, String>{'categoryTitle': category.title},
                // );
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder:
                        (context) =>
                            CategoryRecords(category: category),
                    settings: RouteSettings(name: CategoryRecords.routeName),
                  ),
                );
              },
              child: CategoryGridItem(category: category),
            ),
        ],
      ),
    );
  }
}
