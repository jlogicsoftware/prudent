import 'package:flutter/material.dart';
import 'package:prudent/utils.dart';

import 'navigation_desktop.dart';
import 'navigation_mobile.dart';

class Navigation extends StatelessWidget {
  const Navigation({super.key});

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder:
          (ctx) =>
              isMobile(ctx)
                  ? const NavigationMobile()
                  : const NavigationDesktop(),
    );
  }
}
