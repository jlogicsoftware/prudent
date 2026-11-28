import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prudent_local_store/prudent_local_store.dart';
import 'package:prudent_ui/home_shell.dart';
import 'package:prudent_ui/providers.dart';
import 'package:prudent_ui/splash_screen.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_ui_store/zen_ui_store.dart';

import '../conflicts/prudent_conflict_sources.dart';
import '../integrity/prudent_issue_source.dart';
import '../l10n/generated/local_localizations.dart';
import '../screens/erased_everywhere_screen.dart';
import '../screens/first_run_notice.dart';
import '../widgets/sync_status_slot.dart';
import 'local_providers.dart';
import 'start_failed_page.dart';

/// What Prudent Local shows under the lock: the shared home shell, with — above it, on every launch
/// — why sync is stopped if it is, and the count of conflicts and integrity issues waiting for the
/// person (`zen_ui_store`'s banner: a conflict nobody looks at is a choice nobody makes).
///
/// It also keeps every screen's data in step with the store: a sync that merged something, a
/// conflict settled, an integrity action, or this device's copy erased all re-read what the
/// providers hold, so a balance shown is never older than the store (ADR-113).
class LocalRoot extends ConsumerStatefulWidget {
  const LocalRoot({super.key});

  @override
  ConsumerState<LocalRoot> createState() => _LocalRootState();
}

class _LocalRootState extends ConsumerState<LocalRoot> {
  StreamSubscription<Set<String>>? _changes;
  int? _generation;
  bool? _firstRunSeen;

  @override
  void initState() {
    super.initState();
    unawaited(_readFirstRun());
  }

  /// The device's secret storage failed to answer whether the first-run notice was seen (a Keychain
  /// refusal, `-34018` on an unsigned macOS build): shown as a start failure, never a splash screen
  /// that waits forever.
  ZenError? _storageFailure;

  Future<void> _readFirstRun() async {
    try {
      final seen = await ref.read(lockStorageProvider).read(firstRunSeenKey);
      if (mounted) setState(() => _firstRunSeen = seen != null);
    } on Object catch (e, stack) {
      developer.log(
        'first-run read failed: ${e.runtimeType}',
        name: 'prudent',
        stackTrace: stack,
      );
      if (mounted) {
        setState(
          () => _storageFailure = ZenUnknownError(
            'This device\'s secret storage cannot be read: ${e.runtimeType}',
            stackTrace: stack,
          ),
        );
      }
    }
  }

  void _retryFirstRun() {
    setState(() => _storageFailure = null);
    unawaited(_readFirstRun());
  }

  /// Follows the store the session holds now; a new one (after an erasure) is read afresh.
  void _follow() {
    final session = ref.read(localSessionProvider);
    if (_generation == session.generation) return;
    final first = _generation == null;
    _generation = session.generation;
    unawaited(_changes?.cancel());
    _changes = session.store.changes.listen((_) => _refresh());
    // Found while building, after an erasure: refresh after the frame, since a provider may not be
    // changed while the tree builds.
    if (!first) WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  void _refresh() {
    if (!mounted) return;
    // Every answer read from the repository, figures and their caveats included, and the reminder
    // schedule: a sync can change any of them.
    invalidateRepositoryReads(ref.invalidate);
    ref.read(reminderScheduleRevisionProvider.notifier).bump();
  }

  @override
  void dispose() {
    unawaited(_changes?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(localSessionProvider);
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        _follow();
        if (session.erasedEverywhere) {
          return ErasedEverywhereScreen(session: session);
        }
        final failure = _storageFailure;
        if (failure != null) {
          return StartFailedPage(
            error: failure,
            onRetry: _retryFirstRun,
            isLinux: Platform.isLinux,
          );
        }
        final seen = _firstRunSeen;
        if (seen == null) return const SplashScreen();
        if (!seen) {
          return FirstRunNotice(
            onDone: () => setState(() => _firstRunSeen = true),
          );
        }
        final t = LocalLocalizations.of(context);
        // The banners sit above the shell's own scaffolds, so they need a Material of their own:
        // without one their text takes Flutter's fallback style (48 px, underlined) and a phone
        // screen overflows.
        return Material(
          child: Column(
            children: [
              SyncStatusSlot(session: session),
              ZenConflictBanner(
                store: session.store,
                sources: prudentConflictSources(session.prudent, t),
                issues: [
                  prudentIssueSource(IntegrityRunner(session.prudent), t),
                ],
              ),
              const Expanded(child: HomeShell()),
            ],
          ),
        );
      },
    );
  }
}
