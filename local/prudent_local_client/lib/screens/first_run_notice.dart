import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zen_ui_lock/zen_ui_lock.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../app/local_providers.dart';
import '../l10n/generated/local_localizations.dart';

/// Said once, on the first launch (ADR-100 T2, T5): the data lives only on the person's devices and
/// nobody can recover it if all are lost, and without a PIN anyone holding the unlocked device sees
/// everything. A PIN is offered, never forced (off by default, jZen ADR-065). [onDone] runs after
/// either answer, once the notice is remembered as seen.
class FirstRunNotice extends ConsumerStatefulWidget {
  const FirstRunNotice({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  ConsumerState<FirstRunNotice> createState() => _FirstRunNoticeState();
}

class _FirstRunNoticeState extends ConsumerState<FirstRunNotice> {
  Future<void> _finish({required bool setPin}) async {
    if (setPin) await showZenPinSetup(context, ref.read(pinLockProvider));
    await ref.read(lockStorageProvider).write(firstRunSeenKey, '1');
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final t = LocalLocalizations.of(context);
    final theme = Theme.of(context);
    return ZenPageScaffold(
      title: t.appTitle,
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Semantics(
            header: true,
            child: Text(t.firstRunTitle, style: theme.textTheme.headlineSmall),
          ),
          const SizedBox(height: 16),
          Text(t.firstRunBody),
          const SizedBox(height: 12),
          Text(
            t.firstRunLoss,
            style: TextStyle(color: theme.colorScheme.error),
          ),
          const SizedBox(height: 12),
          Text(t.firstRunPin, style: TextStyle(color: theme.colorScheme.error)),
          const SizedBox(height: 24),
          ZenButton(
            label: t.firstRunSetPin,
            onPressed: () => _finish(setPin: true),
          ),
          const SizedBox(height: 8),
          ZenButton(
            label: t.firstRunNotNow,
            variant: ZenButtonVariant.text,
            onPressed: () => _finish(setPin: false),
          ),
        ],
      ),
    );
  }
}
