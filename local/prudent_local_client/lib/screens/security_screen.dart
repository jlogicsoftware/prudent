import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zen_store_sync/zen_store_sync.dart';
import 'package:zen_ui_lock/zen_ui_lock.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../app/local_providers.dart';
import '../l10n/generated/local_localizations.dart';
import '../widgets/settings_paragraph.dart';

/// The PIN (ADR-100 T2, T4, T25): the switch is `zen_ui_lock`'s; the words before it are Prudent's.
///
/// What a forgotten PIN costs is said before the PIN is turned on, not after: where this device
/// can confirm its owner, a new PIN is set; where it cannot and no other device is paired, the data
/// is erased with nothing else holding a copy, and the person is told to save one first.
class SecurityScreen extends ConsumerWidget {
  const SecurityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = LocalLocalizations.of(context);
    final lock = ref.watch(pinLockProvider);
    final session = ref.watch(localSessionProvider);
    final ownerCheck = ref.watch(ownerCheckAvailableProvider);
    return ZenPageScaffold(
      title: t.securityTitle,
      body: ListenableBuilder(
        listenable: Listenable.merge([lock, session]),
        builder: (context, _) {
          final canConfirmOwner = ownerCheck.value ?? false;
          // iCloud devices share everything through the Apple ID; elsewhere only a paired device holds a copy.
          final alone =
              !session.hasSyncKey &&
              ref.watch(syncKindProvider) != ZenSyncKind.cloudKit;
          return ListView(
            children: [
              if (!lock.isEnabled)
                SettingsParagraph(t.securityNoPinWarning, warning: true),
              ZenPinLockSwitch(lock: lock),
              if (canConfirmOwner)
                SettingsParagraph(t.securityForgetOwnerCheck)
              else if (alone)
                SettingsParagraph(t.securityForgetAlone, warning: true)
              else
                SettingsParagraph(t.securityForgetErase),
              SettingsParagraph(t.securityPeopleNote),
            ],
          );
        },
      ),
    );
  }
}
