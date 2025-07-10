import 'package:flutter/material.dart';
import 'package:prudent/record/records_screen.dart';
import 'package:prudent/screens/overview.dart';
import 'package:prudent/screens/settings.dart';

final List<Widget> navigationPages = [
  const OverviewScreen(),
  const RecordsScreen(),
  const SettingsScreen(),
];

final List<String> navigationTitles = ['Overview', 'Records', 'More'];

final List<IconData> navigationIcons = [Icons.home, Icons.list_alt, Icons.more];
