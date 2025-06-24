import 'package:flutter/material.dart';
import 'package:prudent/navigation/navigation_list.dart';

class NavigationDesktop extends StatefulWidget {
  const NavigationDesktop({super.key});

  @override
  State<NavigationDesktop> createState() => _NavigationDesktopState();
}

class _NavigationDesktopState extends State<NavigationDesktop> {
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
      body: SafeArea(
        child: Row(
          children: <Widget>[
            NavigationRail(
              selectedIndex: currentPageIndex,
              groupAlignment: -1.0,
              onDestinationSelected: _onPageSelected,
              labelType: NavigationRailLabelType.all,
              destinations: List.generate(
                titles.length,
                (index) => NavigationRailDestination(
                  icon: Icon(icons[index]),
                  label: Text(titles[index]),
                ),
              ),
            ),
            const VerticalDivider(thickness: 1, width: 1),
            Expanded(child: pages[currentPageIndex]),
          ],
        ),
      ),
    );
  }
}
