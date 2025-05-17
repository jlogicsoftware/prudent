import 'package:flutter/material.dart';

import '../screens/categories.dart';
import '../records.dart';

class TabsNavigation extends StatefulWidget {
  const TabsNavigation({super.key});

  static int currentPageIndex = 0;

  @override
  State<TabsNavigation> createState() => _TabsNavigationState();
}

class _TabsNavigationState extends State<TabsNavigation> {
  int currentPageIndex = TabsNavigation.currentPageIndex;

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      destinations: [
        NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
        NavigationDestination(icon: Icon(Icons.dashboard), label: 'Chart'),
        NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
        NavigationDestination(
          icon: Icon(Icons.account_circle),
          label: 'Profile',
        ),
      ],
      selectedIndex: currentPageIndex,
      onDestinationSelected: (int index) {
        if (index == currentPageIndex) {
          return;
        }
        TabsNavigation.currentPageIndex = index;
        setState(() {
          currentPageIndex = index;
        });
        switch (index) {
          case 0:
            Navigator.pushNamed(context, '/home');
            break;
          case 1:
            Navigator.pushNamed(context, '/chart');
            break;
          case 2:
            Navigator.pushNamed(context, '/settings');
            break;
          case 3:
            Navigator.pushNamed(context, '/profile');
            break;
        }
      },
      labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
      animationDuration: const Duration(milliseconds: 300),
      height: 60,
    );
  }
}

Map<String, WidgetBuilder> get navigationRoutes {
  return {
    '/home': (context) => const Records(),
    '/chart': (context) => CategoriesScreen(),
    '/settings': (context) => const Center(child: Text('Settings')),
    '/profile': (context) => const Center(child: Text('Profile')),
  };
}

List<Widget> get navigationBody {
  return [
    const Records(),
    CategoriesScreen(),
    const Center(child: Text('Settings')),
    const Center(child: Text('Profile')),
  ];
}
