import 'package:zen_core/zen_core.dart';

import '../prudent_local_store.dart';
import 'checks/category_kind_check.dart';
import 'checks/correction_intent_check.dart';
import 'checks/dangling_reference_check.dart';
import 'checks/default_account_check.dart';
import 'checks/duplicate_account_number_check.dart';
import 'checks/held_currency_check.dart';
import 'checks/live_reset_slot_check.dart';
import 'integrity_issue.dart';
import 'store_snapshot.dart';

/// One rule across records that a merge can break (finding F-05). The extension point of the runner:
/// each unit that owns such a rule adds a check, and the runner never needs to change.
///
/// A check reads; it never writes. What it finds, it returns as [IntegrityIssue]s whose actions write
/// through [store] only when the person chooses them.
abstract interface class IntegrityCheck {
  /// Short, stable, for logs and tests (`dangling_references`).
  String get name;

  /// Every issue this rule finds in [snapshot], as the store stands now.
  Iterable<IntegrityIssue> check(StoreSnapshot snapshot, PrudentLocalStore store);
}

/// Re-evaluates every rule across records after each change to the store — a sync that merged
/// something, or a write on this device — and lists what fails, with its actions (ADR-102 D6). It
/// fixes nothing on its own.
///
/// The list reaches the person through `zen_ui_store`'s app issues beside the store's conflicts
/// (jZenDev/jZen#233, consumed from jZen PR #242): the Local app passes
/// `ZenIssueSource(issues: () => runner.evaluate() mapped to ZenIssues)`, which the banner and the
/// conflict list call whenever the store changes. That wiring needs Flutter, so it is the app's
/// (unit 9); this package is pure Dart.
///
/// [evaluate] reads the store's in-memory records afresh on every call. It keeps no answer between
/// calls: the store announces a change on a stream, after the write that caused it has returned, so a
/// kept answer could be read stale in between — and a stale "no issues" is the one answer this must
/// never give.
final class IntegrityRunner {
  /// The checks of the store model itself (unit 4). Units 5–8 append theirs.
  static final List<IntegrityCheck> storeModelChecks = List.unmodifiable(<IntegrityCheck>[
    const DanglingReferenceCheck(),
    const DefaultAccountCheck(),
    const HeldCurrencyCheck(),
    const CategoryKindCheck(),
    const DuplicateAccountNumberCheck(),
    const LiveResetSlotCheck(),
  ]);

  /// The ledger's checks (unit 5, ADR-113).
  static final List<IntegrityCheck> ledgerChecks = List.unmodifiable(<IntegrityCheck>[
    const CorrectionIntentCheck(),
  ]);

  /// Every check that exists so far, which is what the Local app runs.
  static final List<IntegrityCheck> allChecks = List.unmodifiable(<IntegrityCheck>[
    ...storeModelChecks,
    ...ledgerChecks,
  ]);

  final PrudentLocalStore store;
  final List<IntegrityCheck> checks;

  /// Evaluates [checks] over [store] (by default [allChecks]). Check names must be unique.
  IntegrityRunner(this.store, {List<IntegrityCheck>? checks})
    : checks = List.unmodifiable(checks ?? allChecks) {
    final names = this.checks.map((c) => c.name).toList();
    if (names.toSet().length != names.length) {
      throw ArgumentError.value(names, 'checks', 'name a check twice');
    }
  }

  /// Every issue the store breaks now, ordered by id; or the store's error when a record cannot be
  /// read, which is never reported as "no issues".
  ZenResult<List<IntegrityIssue>> evaluate() {
    final StoreSnapshot snapshot;
    switch (StoreSnapshot.read(store)) {
      case ZenSuccess(:final data):
        snapshot = data;
      case ZenFailure(:final error):
        return ZenResult.err(error);
    }
    final found = <String, IntegrityIssue>{};
    for (final check in checks) {
      for (final issue in check.check(snapshot, store)) {
        if (found.containsKey(issue.id)) {
          throw StateError(
            'check ${check.name} reported ${issue.id}, which another check reported',
          );
        }
        found[issue.id] = issue;
      }
    }
    final ids = found.keys.toList()..sort();
    return ZenResult.ok(List.unmodifiable([for (final id in ids) found[id]!]));
  }

  /// Fires after the store changed, when [evaluate] may answer differently.
  Stream<void> get changes => store.zen.changes.map((_) {});
}
