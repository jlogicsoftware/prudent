import 'package:zen_core/zen_core.dart';
import 'package:zen_store/zen_store.dart';
import 'package:zen_store_shared_folder/zen_store_shared_folder.dart';
import 'package:zen_store_sync/zen_store_sync.dart';

/// Starts sync for a store. The app's only route to a transport is [ZenSync.start] (jZen ADR-079);
/// a test substitutes another starter to run two devices through a transport it controls.
typedef SyncStarter = Future<ZenResult<ZenSyncTransport>> Function(
  ZenStore store, {
  required ZenFolderAccess folder,
  required List<int>? syncKey,
});

/// The CloudKit container an Apple build syncs through: Prudent Local's own, never the
/// server-connected app's (ADR-101). It needs the paid Apple Developer Program and an iCloud
/// entitlement, which this repository does not have yet, so Apple builds develop against
/// `ZEN_SYNC=folder` until unit 12. Record names in it are HMACs (jZenDev/jZen#236), so Apple sees
/// neither a collection nor an id.
const String prudentCloudKitContainer =
    'iCloud.com.jlogicsoftware.prudent.local';

/// What a build does: `ZenSync` chooses the transport from `ZEN_PLATFORM` and `ZEN_SYNC`.
Future<ZenResult<ZenSyncTransport>> startSyncForBuild(
  ZenStore store, {
  required ZenFolderAccess folder,
  required List<int>? syncKey,
}) => ZenSync.start(
  store,
  cloudKitContainerId: prudentCloudKitContainer,
  sharedFolder: folder,
  syncKey: syncKey,
);
