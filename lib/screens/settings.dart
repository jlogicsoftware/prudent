import 'package:flutter/material.dart';
import 'package:prudent/account/account_screen.dart';
import 'package:prudent/category/categories_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Column(
        children: [
          TextButton(
            style: ButtonStyle(splashFactory: NoSplash.splashFactory),
            onPressed:
                () => Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (ctx) => AccountScreen())),
            child: Text('Accounts'),
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
