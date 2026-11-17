import 'package:material_ui/material_ui.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../core/local_session.dart';
import '../l10n/generated/local_localizations.dart';
import 'confirm_step.dart';
import 'settings_action.dart';
import 'settings_heading.dart';
import 'settings_paragraph.dart';

/// Removing a lost, sold or shared device (ADR-100 T3, jZenDev/jZen#237). On the folder transport
/// the sync key is replaced (`LocalSession.removeDevice`), and the page says what that cannot do;
/// on iCloud there is no key of Prudent's to replace, so it says how Apple removes a device. A
/// device is never called "removed" by anything here beyond what the key replacement does.
class RemoveDeviceSection extends StatelessWidget {
  const RemoveDeviceSection({
    super.key,
    required this.session,
    required this.apple,
  });

  final LocalSession session;

  /// Whether this build syncs through iCloud, where Apple, not a sync key, removes a device.
  final bool apple;

  Future<void> _remove(BuildContext context) async {
    final t = LocalLocalizations.of(context);
    final go = await confirmStep(
      context,
      question: '${t.removeDeviceConfirm}\n\n${t.removeDeviceLimits}',
      action: t.removeDeviceButton,
      cancel: t.cancel,
    );
    if (!go || !context.mounted) return;
    final replaced = await session.removeDevice();
    if (!context.mounted) return;
    showZenMessage(
      context,
      replaced is ZenSuccess ? t.removeDeviceDone : t.removeDeviceFailed,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = LocalLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsHeading(t.removeDeviceTitle),
        if (apple)
          SettingsParagraph(t.removeDeviceApple)
        else ...[
          SettingsParagraph(t.removeDeviceHint),
          SettingsParagraph(t.removeDeviceLimits, warning: true),
          SettingsAction(
            label: t.removeDeviceButton,
            onPressed: session.canRemoveDevice ? () => _remove(context) : null,
          ),
        ],
      ],
    );
  }
}
