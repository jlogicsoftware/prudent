import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zen_core/zen_core.dart' show zenIsMobile;

/// Writes [bytes] to a file the person chooses, under the suggested [name]. Returns false when they
/// cancel, true once the file is written. Throws when the platform refuses the write, so a failure
/// is shown rather than reported as a save.
typedef ExportFileSaver = Future<bool> Function(String name, Uint8List bytes);

/// The platform's own save panel (`file_selector`: macOS, Windows and Linux). On the web the browser
/// downloads the file under [name] and decides where it goes, so there is no cancel to report.
///
/// Not offered on iOS and Android: `file_selector`'s implementations there have no save location, and
/// the framework has no save-file capability to use instead (docs/jzen/README.md, ADR-110). See
/// [exportFileSavingSupportedProvider].
Future<bool> saveExportFile(String name, Uint8List bytes) async {
  const json = XTypeGroup(
    label: 'JSON',
    extensions: <String>['json'],
    mimeTypes: <String>['application/json'],
    uniformTypeIdentifiers: <String>['public.json'],
  );
  final file = XFile.fromData(bytes, name: name, mimeType: 'application/json');
  if (kIsWeb) {
    await file.saveTo(name);
    return true;
  }
  final location = await getSaveLocation(
    suggestedName: name,
    acceptedTypeGroups: const <XTypeGroup>[json],
  );
  if (location == null) return false;
  await file.saveTo(location.path);
  return true;
}

/// Overridden in tests with a fake; the app uses [saveExportFile].
final exportFileSaverProvider = Provider<ExportFileSaver>((ref) => saveExportFile);

/// Whether this platform can save the export to a file. False on iOS and Android, where the
/// clipboard copy is the only way out until the framework gains a save-file capability.
final exportFileSavingSupportedProvider = Provider<bool>((ref) => !zenIsMobile);

/// Whether [saveExportFile] hands the file to the browser's downloads rather than to a place the
/// person chose (the web). It only changes the wording of the confirmation: the browser does not say
/// where the file went, so the app cannot claim it was saved somewhere.
final exportFileSavedByDownloadProvider = Provider<bool>((ref) => kIsWeb);
