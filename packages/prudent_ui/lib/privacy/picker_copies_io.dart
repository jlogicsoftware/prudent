import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:zen_core/zen_core.dart';

/// Removes the plaintext copies the platform's file dialogs leave in the app's own sandbox (ADR-138).
/// Only iOS and Android make them:
///
/// | Platform | Where | Made by |
/// |---|---|---|
/// | iOS | `tmp/<bundle id>-Inbox/` | picking a file (`file_selector_ios` opens the picker "as a copy") |
/// | iOS | `tmp/flutter_file_picker/` | saving a file (`file_picker_darwin`; 2.5.1 left it there) |
/// | Android | `cacheDir/<name-based UUID>/` | picking a file (`file_selector_android`) |
///
/// **A file the person owns is never deleted.** On desktop the picker answers with the person's own
/// file, so nothing at all happens there. On iOS and Android the picked path is deleted only when,
/// with every symbolic link and `..` resolved, it lies inside the app's temporary or cache directory;
/// anything else is left alone. The rest of those directories is left alone too: other code and
/// plugins use them.
class PickerCopies {
  /// [temporaryDirectory] and [cacheDirectory] stand in for the platform's directories in a test;
  /// an app passes neither.
  const PickerCopies({this.temporaryDirectory, this.cacheDirectory});

  /// iOS's `tmp/` (`NSTemporaryDirectory`), which is where its dialogs write. Not what
  /// `path_provider` calls the temporary directory there, which is `Library/Caches`.
  final Future<Directory> Function()? temporaryDirectory;

  /// Android's `cacheDir`; on iOS, `Library/Caches`, which only a picked path is looked for in.
  final Future<Directory> Function()? cacheDirectory;

  /// The directory `file_picker_darwin` writes an export into before the save sheet takes it.
  static const String _exports = 'flutter_file_picker';

  /// How iOS names the directory it copies a picked file into, after the app's bundle id.
  static const String _inboxSuffix = '-Inbox';

  /// The directory `file_selector_android` makes for one pick: `UUID.nameUUIDFromBytes` of the
  /// document's URI, so always version 3. A random (version 4) one is another plugin's.
  static final RegExp _androidPick = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-3[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  /// Deletes the copy behind [picked] (the path a picker answered with, if it answered) and every
  /// copy the dialogs are known to leave, including those of an earlier pick, save or build. Call it
  /// only when no dialog is open: a save sheet's file is one of them.
  ///
  /// It fails when a copy may still be there. One that is already gone (another removal, or the
  /// system clearing its cache) is what was asked for, and a copy directory that cannot be deleted
  /// but holds nothing holds no copy. It errs towards failing: a directory *inside* a copy directory
  /// that cannot be deleted fails the removal even when it is empty.
  ///
  /// Never throws. Every removal is tried; the failure it answers with is the first. Each is logged,
  /// naming no path or file (ADR-100 T21).
  Future<ZenResult<void>> remove({String? picked}) async {
    // The platform the app is running on, which only a debug build can override, so that a wrong
    // build define cannot turn this on over a desktop's files or off on a phone (as ADR-137 asks).
    final platform = defaultTargetPlatform;
    final isIos = platform == TargetPlatform.iOS;
    if (!isIos && platform != TargetPlatform.android) return const ZenResult.ok(null);

    ZenError? failure;
    Future<void> attempt(Future<void> Function() step) async {
      try {
        await step();
      } on Object catch (error, stack) {
        // The class only: a file system error's text quotes the path, which can name the file.
        developer.log(
          'A copy left by a file dialog was not removed (${error.runtimeType}).',
          name: 'prudent',
          level: 1000,
          stackTrace: stack,
        );
        failure ??= ZenUnknownError(
          'A copy left by a file dialog was not removed: ${error.runtimeType}',
          stackTrace: stack,
        );
      }
    }

    final roots = <Directory>[];
    Directory? temporary;
    Directory? cache;
    if (isIos) {
      await attempt(() async {
        temporary = await (temporaryDirectory ?? _systemTemp)();
        roots.add(temporary!);
      });
    }
    // On iOS nothing is swept in the cache directory, so without a picked path it is not asked for:
    // a failure to name it would say a copy may remain when none could be there.
    if (!isIos || picked != null) {
      await attempt(() async {
        cache = await (cacheDirectory ?? getTemporaryDirectory)();
        roots.add(cache!);
      });
    }

    if (picked != null) await attempt(() => _unlessGone(() => _deleteInside(picked, roots)));

    /// Deletes [directory] and what it holds, entry by entry, so that one that fails or is already
    /// gone does not stop the rest. A link found in it is deleted as a link, not listed into.
    Future<void> deleteCopies(Directory directory) => attempt(
      () => _unlessGone(() async {
        // `followLinks` governs the entries listed, not the path being opened: a directory swapped
        // for a link since its parent was listed would have its target listed, and emptied. This
        // narrows that to the time between this check and the listing; it does not close it.
        // Anything but a link goes on, so that one that cannot be looked at still fails.
        final type = await FileSystemEntity.type(directory.path, followLinks: false);
        if (type == FileSystemEntityType.link) return;
        await for (final entry in directory.list(followLinks: false)) {
          if (entry is Directory) {
            await deleteCopies(entry);
          } else {
            await attempt(() => _unlessGone(entry.delete));
          }
        }
        try {
          await directory.delete();
        } on FileSystemException {
          // It stays. That matters only if something is still in it.
          if (!await directory.list(followLinks: false).isEmpty) rethrow;
        }
      }),
    );

    final swept = isIos ? temporary : cache;
    if (swept != null) {
      await attempt(
        () => _unlessGone(() async {
          await for (final entry in swept.list(followLinks: false)) {
            // A directory of the dialog's own making; a link that merely has such a name is not one.
            if (entry is! Directory) continue;
            final name = entry.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
            final ours = isIos
                ? name == _exports || name.endsWith(_inboxSuffix)
                : _androidPick.hasMatch(name);
            if (ours) await deleteCopies(entry);
          }
        }),
      );
    }

    final error = failure;
    return error == null ? const ZenResult.ok(null) : ZenResult.err(error);
  }

  static Future<Directory> _systemTemp() async => Directory.systemTemp;

  /// Runs [step], a removal. That what it was to remove, or the directory it was in, is already gone
  /// is what was asked for.
  static Future<void> _unlessGone(Future<void> Function() step) async {
    try {
      await step();
    } on PathNotFoundException {
      // Gone.
    }
  }

  /// Deletes the file at [path] if it really is inside one of [roots]. Both sides are resolved first:
  /// iOS spells one directory as `/var/…` and `/private/var/…`, Android as `/data/user/0/…` and
  /// `/data/data/…`, and a `..` or a link may leave a directory that a prefix of the text is inside.
  static Future<void> _deleteInside(String path, List<Directory> roots) async {
    if (await FileSystemEntity.type(path) != FileSystemEntityType.file) return;
    final resolved = await File(path).resolveSymbolicLinks();
    for (final root in roots) {
      if (!await root.exists()) continue;
      final inside = '${await root.resolveSymbolicLinks()}${Platform.pathSeparator}';
      if (resolved.startsWith(inside)) {
        await File(resolved).delete();
        return;
      }
    }
  }
}
