import 'package:material_ui/material_ui.dart';
import 'package:prudent_ui/failure_code.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_store/zen_ui_store.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../core/local_session.dart';
import '../l10n/generated/local_localizations.dart';
import 'settings_action.dart';
import 'settings_paragraph.dart';

/// The folder and the pairing on Android, Windows and Linux, which sync through a folder a sync
/// service of the person's keeps in step: choose it (after the warning of ADR-100 T6), then make
/// this the first device, join one, or add one. The pairing screens are `zen_ui_store`'s.
class SharedFolderControls extends StatelessWidget {
  const SharedFolderControls({super.key, required this.session});

  final LocalSession session;

  void _push(BuildContext context, Widget screen) =>
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => screen));

  Future<void> _chooseFolder(BuildContext context) async {
    final t = LocalLocalizations.of(context);
    final chosen = await session.chooseFolder();
    if (!context.mounted) return;
    if (chosen case ZenFailure(:final error)) {
      showZenMessage(
        context,
        failureCode(error) == 'folder_inside_app_data'
            ? t.syncFolderInsideApp
            : t.syncFolderFailed,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = LocalLocalizations.of(context);
    final folder = session.folder;
    final key = session.syncKey;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsParagraph(
          '${t.syncFolder}: ${folder?.label ?? t.syncFolderNone}',
        ),
        SettingsParagraph(t.syncFolderWarning, warning: true),
        SettingsAction(
          label: folder == null ? t.syncChooseFolder : t.syncChangeFolder,
          onPressed: () => _chooseFolder(context),
        ),
        if (key == null) ...[
          SettingsParagraph(t.syncFirstDeviceHint),
          SettingsAction(
            label: t.syncFirstDevice,
            onPressed: () async {
              final made = await session.createSyncKey();
              if (!context.mounted) return;
              showZenMessage(
                context,
                made is ZenSuccess ? t.syncKeyMade : t.syncKeyFailed,
              );
            },
          ),
          SettingsAction(
            label: t.syncJoin,
            onPressed: () => _push(
              context,
              ZenJoinScreen(
                onKey: (joined) async {
                  final adopted = await session.adoptSyncKey(joined);
                  if (context.mounted && adopted is ZenSuccess) {
                    Navigator.of(context).pop();
                    showZenMessage(context, t.syncKeyJoined);
                  }
                  return adopted;
                },
                onCancel: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        ] else
          SettingsAction(
            label: t.syncAddDevice,
            onPressed: () => _push(
              context,
              ZenAddDeviceScreen(
                syncKey: key,
                onClose: () => Navigator.of(context).pop(),
              ),
            ),
          ),
      ],
    );
  }
}
