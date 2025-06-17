import 'package:flutter/material.dart';

class OverviewScreen extends StatelessWidget {
  const OverviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // title: Text(titles[currentPageIndex]),
        actions: [
          IconButton(
            icon: const Icon(Icons.list),
            onPressed: () => Navigator.pushNamed(context, '/records'),
          ),
          IconButton(
            icon: const Icon(Icons.dashboard_customize),
            onPressed: () => Navigator.pushNamed(context, '/categories'),
          ),
        ],
      ),
      body: Center(
        child: Text(
          'Overview Screen',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
