import 'package:flutter/material.dart';
import 'package:prudent/record/records_screen.dart';
import 'package:prudent/screens/analytics.dart';
import 'package:prudent/screens/overview.dart';
import 'package:prudent/screens/settings.dart';

final List<Widget> navigationPages = [
  const OverviewScreen(),
  const RecordsScreen(),
  const AnalyticsScreen(),
  const SettingsScreen(),
];

final List<String> navigationTitles = [
  'Overview',
  'Records',
  'Analytics',
  'Settings',
];

final List<IconData> navigationIcons = [
  Icons.home,
  Icons.swap_vert_outlined,
  Icons.analytics_outlined,
  Icons.settings,
];
