import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_store_cloudkit/zen_store_cloudkit.dart';

/// The `internalData['code']` of a store directory that could not be given iOS Data Protection.
const String dataProtectionFailedCode = 'data_protection_failed';

/// On iOS, gives the store's [directory] Data Protection `complete` (ADR-100 T1, ADR-137): its files
/// are unreadable while the device is locked, and what the store writes there later takes the same
/// class. Call it before every `ZenStore.open`: erasing a copy deletes the directory, so the one
/// opened afterwards is new and unprotected.
///
/// Anywhere else it does nothing: no other platform has this class, and the store's own encryption is
/// what protects the files there. The platform asked is the one the app is running on
/// ([defaultTargetPlatform], which only a debug build can override), not the build's `ZEN_PLATFORM`,
/// so a build with a wrong or missing define cannot drop the protection.
///
/// On iOS anything but "it is set" fails, so nothing is opened without it. That includes jZen's
/// `false`, which on an iPhone means the plugin is not registered.
Future<ZenResult<void>> protectStoreDirectory(Directory directory) async {
  if (defaultTargetPlatform != TargetPlatform.iOS) {
    return const ZenResult.ok(null);
  }
  return switch (await ZenDataProtection.protectDirectory(directory)) {
    ZenSuccess(data: true) => const ZenResult.ok(null),
    ZenSuccess() => ZenResult.err(
      const ZenUnknownError(
        'iOS Data Protection was not set: the plugin that sets it did not answer.',
        internalData: {'code': dataProtectionFailedCode},
      ),
    ),
    ZenFailure(:final error) => ZenResult.err(
      ZenUnknownError(
        error.message,
        internalData: const {'code': dataProtectionFailedCode},
        stackTrace: error.stackTrace,
      ),
    ),
  };
}
