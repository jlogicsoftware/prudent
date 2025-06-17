import 'package:flutter/material.dart';
import 'package:prudent/navigation_list.dart';

class NavigationMobile extends StatefulWidget {
  const NavigationMobile({super.key});

  @override
  State<NavigationMobile> createState() => _NavigationMobileState();
}

class _NavigationMobileState extends State<NavigationMobile> {
  int currentPageIndex = 0;

  final List<Widget> pages = navigationPages;
  final List<String> titles = navigationTitles;
  final List<IconData> icons = navigationIcons;

  void _onPageSelected(int index) {
    setState(() {
      currentPageIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: pages[currentPageIndex],
      bottomNavigationBar: NavigationBar(
        destinations: List.generate(
          titles.length,
          (index) => NavigationDestination(
            icon: Icon(icons[index]),
            label: titles[index],
          ),
        ),
        selectedIndex: currentPageIndex,
        onDestinationSelected: _onPageSelected,
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
      ),
    );
  }
}
