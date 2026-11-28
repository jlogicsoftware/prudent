import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:prudent_ui/privacy/picker_copies.dart';

/// The largest export file the move reads (64 MiB): far above any ledger a person keeps by hand,
/// and a bound on what is read into memory from a file nobody vouched for.
const int maxExportFileBytes = 64 * 1024 * 1024;

/// The file was larger than [maxExportFileBytes]; it was not read.
final class ExportFileTooLarge implements Exception {
  const ExportFileTooLarge();

  @override
  String toString() => 'ExportFileTooLarge';
}

/// Asks the person for the export file they saved from the server app (unit 10b, ADR-123) through
/// the platform's own picker (`file_selector`: a sheet on iOS, a panel on desktop, the document
/// picker on Android). The app sees only the file picked and holds no storage permission. Null when
/// they cancel; never the clipboard (ADR-100 T14).
///
/// iOS and Android hand the file over as a plaintext copy in the app's own sandbox. [copies] removes
/// it before this answers, whether the file was read, refused or could not be read (ADR-138).
Future<Uint8List?> pickExportFile({PickerCopies copies = const PickerCopies()}) async {
  const json = XTypeGroup(
    label: 'JSON',
    extensions: <String>['json'],
    mimeTypes: <String>['application/json'],
    uniformTypeIdentifiers: <String>['public.json'],
  );
  XFile? file;
  try {
    file = await openFile(acceptedTypeGroups: <XTypeGroup>[json]);
    if (file == null) return null;
    if (await file.length() > maxExportFileBytes) throw const ExportFileTooLarge();
    return await file.readAsBytes();
  } finally {
    // Also after a dialog that failed: Android may have written part of a copy by then. A removal
    // that fails is logged there and tried again at the next pick or launch.
    await copies.remove(picked: file?.path);
  }
}
