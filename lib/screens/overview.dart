import 'package:flutter/material.dart';
import 'package:prudent/account/account_screen.dart';
import 'package:prudent/chart/chart_screen.dart';

class OverviewScreen extends StatelessWidget {
  const OverviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Prudent'),
        actions: [
          IconButton(
            icon: const Icon(Icons.pie_chart_outline),
            onPressed: () => Navigator.pushNamed(context, ChartScreen.routName),
          ),
          IconButton(
            icon: const Icon(Icons.list),
            onPressed:
                () => Navigator.pushNamed(context, AccountScreen.routeName),
          ),
        ],
      ),
      body: Center(
        child: Column(
          children: [
            Text(
              'Chart',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            Text(
              'Accounts overview',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}
