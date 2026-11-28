import 'package:zen_core/zen_core.dart';

/// The web's [PickerCopies]: a browser hands the page the bytes of the file the person picked and
/// writes no copy the app could reach, so there is nothing to remove.
class PickerCopies {
  const PickerCopies();

  /// Succeeds at once; [picked] is a browser's own object URL, never a path.
  Future<ZenResult<void>> remove({String? picked}) async => const ZenResult.ok(null);
}
