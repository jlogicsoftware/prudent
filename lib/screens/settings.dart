import 'package:flutter/material.dart';
import 'package:prudent/category/categories_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Column(
        children: [
          InkWell(
            child: Text('Categories'),
            onTap:
                () => Navigator.pushNamed(context, CategoriesScreen.routeName),
          ),
          TextButton(
            style: ButtonStyle(splashFactory: NoSplash.splashFactory),
            onPressed:
                () => Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (ctx) => CategoriesScreen())),
            child: Text('Categories'),
          ),
          Text('Corespondents'),
          Text('Language'),
          Text('Profile'),
          Text('Help'),
        ],
      ),
    );
  }
}
