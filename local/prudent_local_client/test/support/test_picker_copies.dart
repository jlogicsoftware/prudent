import 'dart:io';

import 'package:prudent_ui/privacy/picker_copies.dart';

/// A session's file-dialog directories in a test: two of the test's own, under [root]. Without this
/// a session would ask the platform, which a test host has no plugin for (and, told it is iOS, would
/// sweep the host's own temporary directory).
PickerCopies testPickerCopies(Directory root) => PickerCopies(
  temporaryDirectory: () async => Directory('${root.path}/tmp'),
  cacheDirectory: () async => Directory('${root.path}/cache'),
);
