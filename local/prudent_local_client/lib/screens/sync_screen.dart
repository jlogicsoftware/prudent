import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zen_store_sync/zen_store_sync.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../app/local_providers.dart';
import '../l10n/generated/local_localizations.dart';
import '../widgets/remove_device_section.dart';
import '../widgets/settings_heading.dart';
import '../widgets/settings_paragraph.dart';
import '../widgets/shared_folder_controls.dart';
import '../widgets/sync_status_slot.dart';

/// Settings → Sync and devices: how this device syncs, in the build's own terms (iCloud on Apple, a
/// folder and a pairing code elsewhere, a development folder with `ZEN_SYNC=folder`), adding,
/// joining and removing devices, and what nobody can recover (ADR-100 T3, T5, T6, T17).
class SyncScreen extends ConsumerWidget {
  const SyncScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = LocalLocalizations.of(context);
    final session = ref.watch(localSessionProvider);
    final plan = ZenSync.plan;
    final kind = ref.watch(syncKindProvider);
    return ZenPageScaffold(
      title: t.syncTitle,
      body: ListenableBuilder(
        listenable: session,
        builder: (context, _) => ListView(
          children: [
            SyncStatusSlot(session: session),
            SettingsHeading(t.syncTitle),
            switch (kind) {
              ZenSyncKind.sharedFolder => SharedFolderControls(
                session: session,
              ),
              ZenSyncKind.cloudKit => SettingsParagraph(t.syncApple),
              ZenSyncKind.folderCloud => SettingsParagraph(
                t.syncDevelopmentFolder,
                warning: true,
              ),
              null => SettingsParagraph(
                t.syncRefused(plan.refusal ?? ''),
                warning: true,
              ),
            },
            RemoveDeviceSection(
              session: session,
              apple: kind == ZenSyncKind.cloudKit,
            ),
            SettingsParagraph(t.syncLossWarning, warning: true),
          ],
        ),
      ),
    );
  }
}
