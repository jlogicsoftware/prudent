import 'package:flutter/material.dart';
import 'package:prudent/models/category.dart';

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
          childAspectRatio: 3 / 2,
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
                print('Category tapped: ${category.title}');
                return;
                Navigator.pushNamed(
                  context,
                  '/category-details',
                  arguments: category,
                );
              },
              child: CategoryGridItem(category: category),
            ),
        ],
      ),
    );
  }
}
