import 'package:fixnum/fixnum.dart';
import 'package:prudent_local_core/prudent_local_core.dart';
import 'package:zen_core/zen_core.dart';

import '../../../generated/prudent_local/v1/store.pb.dart';
import '../../ledger/ledger_view.dart';
import '../../prudent_local_store.dart';
import '../integrity_issue.dart';
import '../integrity_runner.dart';
import '../store_snapshot.dart';

/// Corrections of one account and currency made without seeing each other (ADR-102 D7, ADR-113).
///
/// A correction stores the server's meaning — the delta from the balance at that moment
/// (`CorrectionResource.java:95–110`) — so that Local's figures are the server's. Two devices that
/// each correct the same balance offline each store a delta from the same starting point, and the
/// merged balance overshoots by one of them: the person asked for one balance and got neither. On the
/// server the second correction would have seen the first and stored a different delta (or been
/// refused as changing nothing). Each correction records the other corrections of its account and
/// currency it saw (`CorrectionIntent.seen_corrections`); two that do not name each other were made
/// apart, and every such group is one issue.
///
/// What this does **not** flag, on purpose: a record from another device that a correction did not
/// see. With deltas the merged balance is the one the server would show had the record come after the
/// correction, and nothing on the device says which came first in the world — the wall clock decides
/// nothing (ADR-102). Only a second correction makes the result one no order could give.
///
/// The person deletes one of them, or replaces the group by one correction to the balance one of them
/// asked for.
final class CorrectionIntentCheck implements IntegrityCheck {
  const CorrectionIntentCheck();

  @override
  String get name => 'correction_intent';

  @override
  Iterable<IntegrityIssue> check(StoreSnapshot snapshot, PrudentLocalStore store) sync* {
    final byBalance = <(String, String), List<Record>>{};
    for (final record in snapshot.records.values) {
      if (!record.hasCorrection()) continue;
      final key = (record.posting.accountId, record.posting.currency);
      (byBalance[key] ??= []).add(record);
    }
    for (final MapEntry(key: (accountId, currency), value: corrections) in byBalance.entries) {
      for (final group in _madeApart(corrections)) {
        final ids = [for (final r in group) r.id]..sort();
        yield IntegrityIssue(
          code: 'correction.made_apart',
          collection: 'records',
          recordId: ids.first,
          key: ids.join('+'),
          facts: {'accountId': accountId, 'currency': currency, 'corrections': ids.join(',')},
          actions: [
            IntegrityAction.choose('delete_correction', ids, store.deleteRecord),
            IntegrityAction.choose(
              'correct_to_target',
              ids,
              (chosen) => _replaceByOne(store, ids, chosen),
            ),
          ],
        );
      }
    }
  }

  /// The groups of corrections joined by "neither saw the other", each of two or more.
  ///
  /// **Transitive on purpose.** A and C may have seen each other while B saw neither: B was made
  /// apart from both, so all three are one question about one balance, and one issue. Splitting it
  /// into pairwise issues would offer "replace A and B by one correction" while C still changes the
  /// same balance — an answer that leaves the balance wrong. Do not "fix" this into pairs.
  static List<List<Record>> _madeApart(List<Record> corrections) {
    bool apart(Record a, Record b) =>
        !a.correction.seenCorrections.contains(b.id) &&
        !b.correction.seenCorrections.contains(a.id);
    final groups = <List<Record>>[];
    final placed = <String>{};
    final sorted = corrections.toList()..sort((a, b) => a.id.compareTo(b.id));
    for (final start in sorted) {
      if (placed.contains(start.id)) continue;
      final group = <Record>[start];
      placed.add(start.id);
      for (var i = 0; i < group.length; i++) {
        for (final other in sorted) {
          if (!placed.contains(other.id) && apart(group[i], other)) {
            placed.add(other.id);
            group.add(other);
          }
        }
      }
      if (group.length > 1) groups.add(group);
    }
    return groups;
  }

  /// Deletes every correction of the group and writes one correction that brings the balance to
  /// what [chosen] asked for, from the balance without the group — as one write. Run against the
  /// store as it stands when the person acts.
  static Future<ZenResult<Object?>> _replaceByOne(
    PrudentLocalStore store,
    List<String> ids,
    String chosen,
  ) async {
    final LedgerView view;
    try {
      view = LedgerView.read(store);
    } on LedgerReadFailure catch (failure) {
      return ZenResult.err(failure.error);
    }
    final target = view.records[chosen];
    if (target == null || !target.hasCorrection()) {
      return ZenResult.err(ZenNotFoundError('records/$chosen is no longer a correction here.'));
    }
    final accountId = target.posting.accountId;
    final currency = target.posting.currency;
    if (view.unsettledIn(accountId, currency).isNotEmpty || !view.accounts.containsKey(accountId)) {
      return ZenResult.err(
        const ZenConflictError('This balance is not settled; settle its conflicts first.'),
      );
    }
    final group = [for (final id in ids) ?view.records[id]];
    final int without;
    final int delta;
    try {
      without = subtractExact(
        view.balancesOf(accountId).minor[currency] ?? 0,
        sumExact(group.map((r) => r.posting.amountMinor.toInt())),
      );
      delta = subtractExact(target.correction.targetMinor.toInt(), without);
    } on MoneyOverflow catch (e) {
      return ZenResult.err(ZenUnknownError('A figure left the range of minor units ($e).'));
    }
    final batch = StoreBatch(store);
    for (final r in group) {
      batch.deleteRecord(r.id);
    }
    if (delta != 0) {
      final replacement = Record(
        id: store.newId(),
        posting: Posting(accountId: accountId, currency: currency, amountMinor: Int64(delta)),
        date: target.date,
        correction: CorrectionIntent(
          seenCorrections: [
            for (final r in view.records.values)
              if (r.hasCorrection() &&
                  r.posting.accountId == accountId &&
                  r.posting.currency == currency &&
                  !ids.contains(r.id))
                r.id,
          ]..sort(),
        ),
      );
      if (target.hasTitle()) replacement.title = target.title;
      if (target.correction.hasTargetMinor()) {
        replacement.correction.targetMinor = target.correction.targetMinor;
      }
      if (without != 0) replacement.correction.seenMinor = Int64(without);
      if (target.hasNote()) replacement.note = target.note;
      batch.putRecord(replacement);
    }
    return store.writeAll(batch);
  }
}
