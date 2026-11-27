import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zen_save_file/zen_save_file.dart';

/// Writes [bytes] to a file the person chooses, under the suggested [name]. Returns false when they
/// cancel, true once the file is written. Throws a [ZenSaveFileError] when the platform refuses the
/// write, so a failure is shown rather than reported as a save.
typedef ExportFileSaver = Future<bool> Function(String name, Uint8List bytes);

/// The framework's save capability (`zen_save_file`, jZenDev/jZen#246, ADR-117): the save or
/// share-to-Files sheet on iOS and Android, the save panel on desktop, a download on the web. One
/// path for every platform, so the screen never branches on one. [port] stands in for the plugin in
/// a test of this function; the app never passes it.
///
/// On the web the browser downloads the file under [name] and decides where it goes, so there is no
/// cancel to report. See [exportFileSavedByDownloadProvider]. The framework answers false there all
/// the same (jZenDev/jZen#283), so until that is fixed the screen shows no confirmation on the web.
///
/// On macOS the runner needs the `files.user-selected.read-write` entitlement (jZenDev/jZen#282).
Future<bool> saveExportFile(String name, Uint8List bytes, {ZenSaveFilePort? port}) =>
    zenSaveFile(name, bytes, mimeType: 'application/json', port: port);

/// Overridden in tests with a fake; the app uses [saveExportFile].
final exportFileSaverProvider = Provider<ExportFileSaver>((ref) => saveExportFile);

/// Whether [saveExportFile] hands the file to the browser's downloads rather than to a place the
/// person chose (the web). It only changes the wording of the confirmation: the browser does not say
/// where the file went, so the app cannot claim it was saved somewhere.
final exportFileSavedByDownloadProvider = Provider<bool>((ref) => kIsWeb);
