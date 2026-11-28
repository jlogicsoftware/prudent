import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_widgets/zen_ui_widgets.dart';

import '../core/local_session.dart';
import '../l10n/generated/local_localizations.dart';
import '../widgets/copy_may_remain_notice.dart';

/// What the app shows once the person's data was erased everywhere — here, or on another device
/// whose erasure reached this one (jZenDev/jZen#239). The store then holds nothing and refuses every
/// write; starting again is the person's step, never automatic, so an erasure that keeps arriving
/// from the sync place can never loop.
class ErasedEverywhereScreen extends StatefulWidget {
  const ErasedEverywhereScreen({super.key, required this.session});

  final LocalSession session;

  @override
  State<ErasedEverywhereScreen> createState() => _ErasedEverywhereScreenState();
}

class _ErasedEverywhereScreenState extends State<ErasedEverywhereScreen> {
  bool _busy = false;

  Future<void> _start(LocalLocalizations t) async {
    setState(() => _busy = true);
    // Taken now: starting again replaces this screen before it answers.
    final navigator = Navigator.of(context, rootNavigator: true);
    final started = await widget.session.startAfresh();
    if (started case ZenSuccess(data: LocalErasure.copyMayRemain)) {
      unawaited(showCopyMayRemainNotice(navigator, t));
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (started is ZenFailure) showZenMessage(context, t.erasedFailed);
  }

  @override
  Widget build(BuildContext context) {
    final t = LocalLocalizations.of(context);
    final theme = Theme.of(context);
    return ZenPageScaffold(
      title: t.appTitle,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                header: true,
                child: Text(
                  t.erasedTitle,
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 12),
              Text(t.erasedBody, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              ZenButton(
                label: t.erasedStart,
                onPressed: _busy ? null : () => _start(t),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
