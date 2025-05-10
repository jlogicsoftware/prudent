import 'package:flutter/material.dart';

class TabsNavigation extends StatefulWidget {
  const TabsNavigation({super.key});

  static int currentPageIndex = 0;
  static const List<Widget> pages = [
    Text('Home'),
    Text('Chart'),
    Text('Settings'),
    Text('Profile'),
  ];

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
