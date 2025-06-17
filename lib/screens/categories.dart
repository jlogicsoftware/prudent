import 'package:flutter/material.dart';
import 'package:prudent/models/category.dart';
import 'package:prudent/screens/category_records.dart';
import 'package:prudent/utils.dart';

import '../widgets/category_grid_items.dart';

class CategoriesScreen extends StatelessWidget {
  CategoriesScreen({super.key});

  static const routeName = '/categories';

  final List<Category> categories = Category.categories;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      body: GridView(
        padding: const EdgeInsets.all(20),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
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
                            CategoryRecords(categoryTitle: category.title),
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
