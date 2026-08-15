import 'package:flutter/material.dart';

bool isMobile(BuildContext context) {
  return Theme.of(context).platform == TargetPlatform.iOS ||
      Theme.of(context).platform == TargetPlatform.android;
}

bool isApple(BuildContext context) {
  return Theme.of(context).platform == TargetPlatform.iOS ||
      Theme.of(context).platform == TargetPlatform.macOS;
}
