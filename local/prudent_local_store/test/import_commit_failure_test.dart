// Unit 8b (ADR-114): the server's ImportCommitFailureTest on Local — everything that can go wrong
// between a preview and its commit — plus what only Local has: a crash inside the ledger's batch,
// and a crash between the ledger's write and the session's, which are two stores.
//
// Every refusal must name a rule and rows and quote nothing, write nothing, and leave the review
// there to be fixed; every crash must end, after the next launch, with each row in the ledger once —
// including a duplicate the person chose to include, whose occurrence is chosen at commit time.
import 'package:fixnum/fixnum.dart';
import 'package:prudent_local_core/prudent_local_core.dart';
import 'package:prudent_local_store/prudent_local_store.dart';
import 'package:prudent_proto/generated/prudent/v1/accounts.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/categories.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/imports.pb.dart' as wire;
import 'package:test/test.dart';
import 'package:zen_core/zen_core.dart';

import 'support/imports.dart';

void main() {
  late ImportWorld w;
  late String erste;
  late String spending;
  late String income;
  late String other;

  setUp(() async {
    w = await ImportWorld.create();
    erste = await w.account();
    spending = await w.category('Spending', kind: wire.CategoryKind.CATEGORY_KIND_EXPENSE);
    income = await w.category('Income', kind: wire.CategoryKind.CATEGORY_KIND_INCOME);
    other = await w.category('Other');
  });
  tearDown(() => w.dispose());

  Future<wire.ImportSession> previewed() =>
      w.previewed(Erste.base(), account: erste, expense: spending, income: income);

  /// A 409 with exactly [message], naming no category or account by its name.
  void assertRule(ZenError refused, String message) {
    expect(refused.message, message);
    expect(refused.internalData?['code'], 'conflict');
    for (final name in ['Spending', 'Income', 'Other', 'Erste']) {
      expect(refused.message.contains(name), isFalse);
    }
  }

  Future<void> assertStillOpenAndEmpty(String id) async {
    expect(w.records(), isEmpty);
    final read = ok(await w.imports.get(id));
    expect(read.state, wire.ImportSessionState.IMPORT_SESSION_STATE_PREVIEWED);
    expect(read.rows, hasLength(5), reason: 'the review is still there to be fixed');
    expect(ok(w.sessions.sessions.get(id)).hasCommitPlan(), isFalse);
  }

  Future<void> editCategory(String id, {wire.CategoryKind? kind}) async {
    final c = ok(await w.ledger.getCategory(id));
    ok(
      await w.ledger.updateCategory(
        id,
        wire.UpdateCategoryRequest(title: c.title, iconKey: c.iconKey, kind: kind ?? c.kind),
      ),
    );
  }

  Future<void> editAccount({bool active = true, List<String> currencies = const ['PLN']}) async {
    ok(
      await w.ledger.updateAccount(
        erste,
        wire.UpdateAccountRequest(
          name: 'Erste',
          type: wire.AccountType.ACCOUNT_TYPE_CHECKING,
          isActive: active,
          accountNumber: Erste.account,
          balances: [
            for (final c in currencies) wire.CurrencyBalance(currency: c, amountMinor: Int64.ZERO),
          ],
        ),
      ),
    );
  }

  group('the world changes after the preview', () {
    test(
      'a category removed after it was chosen is named by rule and rows; nothing is written',
      () async {
        final s = await previewed();
        ok(await w.ledger.deleteCategory(spending));
        assertRule(
          refused(await w.commit(s.id, 5), 409),
          'The statement was rejected at rows 1, 2, 4, 5 (commit.category_unavailable).',
        );
        await assertStillOpenAndEmpty(s.id);
        ok(await w.defaults(s.id, expense: other));
        expect(ok(await w.commit(s.id, 5)).committedWritten, 5);
        expect(await w.net(erste), Erste.baseNet);
      },
    );

    test('a category archived after it was chosen for one row is named by that row', () async {
      final s = await previewed();
      ok(await w.row(s.id, 2, category: other));
      ok(await w.ledger.archiveCategory(other));
      assertRule(
        refused(await w.commit(s.id, 5), 409),
        'The statement was rejected at row 2 (commit.category_unavailable).',
      );
      await assertStillOpenAndEmpty(s.id);
      ok(await w.ledger.restoreCategory(other));
      expect(ok(await w.commit(s.id, 5)).committedWritten, 5);
    });

    test('a category that now files only the other direction is refused for those rows', () async {
      final s = await previewed();
      await editCategory(income, kind: wire.CategoryKind.CATEGORY_KIND_EXPENSE);
      assertRule(
        refused(await w.commit(s.id, 5), 409),
        'The statement was rejected at row 3 (commit.category_unavailable).',
      );
      await assertStillOpenAndEmpty(s.id);
    });

    test(
      'a statement whose every row lost its category names ten rows and counts the rest',
      () async {
        final s = await w.previewed(
          ErsteStatements.manyCards(13),
          account: erste,
          expense: spending,
          income: income,
        );
        ok(await w.ledger.deleteCategory(spending));
        assertRule(
          refused(await w.commit(s.id, 13), 409),
          'The statement was rejected at rows 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 and 3 more '
          '(commit.category_unavailable).',
        );
        expect(w.records(), isEmpty);
      },
    );

    test(
      'an account renumbered after the preview is refused; the old number restores it',
      () async {
        final s = await previewed();
        await w.renumber(erste, Erste.otherAccount);
        assertRule(
          refused(await w.commit(s.id, 5), 409),
          'The statement was rejected (account.identity_mismatch).',
        );
        await assertStillOpenAndEmpty(s.id);
        await w.renumber(erste, null);
        assertRule(
          refused(await w.commit(s.id, 5), 409),
          'The statement was rejected (account.number_missing).',
        );
        expect(w.records(), isEmpty);
        await w.renumber(erste, Erste.account);
        expect(ok(await w.commit(s.id, 5)).committedWritten, 5);
      },
    );

    test('an account that stopped being usable is named by rule; nothing is written', () async {
      final s = await previewed();
      const unavailable = 'The statement was rejected (commit.account_unavailable).';
      await editAccount(active: false);
      assertRule(refused(await w.commit(s.id, 5), 409), unavailable);
      await assertStillOpenAndEmpty(s.id);
      await editAccount(currencies: ['EUR']);
      assertRule(refused(await w.commit(s.id, 5), 409), unavailable);
      expect(w.records(), isEmpty);
      await editAccount();
      expect(ok(await w.commit(s.id, 5)).committedWritten, 5);
      expect(await w.net(erste), Erste.baseNet);
    });

    test('a destination deleted together with its records cannot receive the commit', () async {
      final s = await previewed();
      ok(await w.ledger.deleteAccount(erste, deleteRecords: true));
      assertRule(
        refused(await w.commit(s.id, 5), 409),
        'The statement was rejected (commit.account_unavailable).',
      );
      expect(w.records(), isEmpty);
      expect(
        ok(await w.imports.get(s.id)).state,
        wire.ImportSessionState.IMPORT_SESSION_STATE_PREVIEWED,
      );
      expect(
        ok(await w.imports.discard(s.id)).state,
        wire.ImportSessionState.IMPORT_SESSION_STATE_DISCARDED,
      );
    });
  });

  group('the session ends under the person', () {
    test('a session that expired mid-flow cannot be committed and is ended by seeing it', () async {
      final s = await previewed();
      w.nowMs += const Duration(hours: 24).inMilliseconds;
      expect(refused(await w.commit(s.id, 5), 409).message, contains('expired'));
      expect(w.records(), isEmpty);
      final read = ok(await w.imports.get(s.id));
      expect(read.state, wire.ImportSessionState.IMPORT_SESSION_STATE_EXPIRED);
      expect(read.rows, isEmpty);
      final again = await previewed();
      expect(ok(await w.commit(again.id, 5)).committedWritten, 5);
    });

    test('two commits of one session at once: the same answer, written once', () async {
      final s = await previewed();
      final both = await Future.wait([w.commit(s.id, 5), w.commit(s.id, 5)]);
      expect(ok(both[0]), ok(both[1]));
      expect(w.records(), hasLength(5));
      expect(refused(await w.commit(s.id, 4), 409).message, contains('different number'));
      refused(await w.preview(s.id), 409);
      expect(w.records(), hasLength(5));
    });

    test('a discard and a commit of one session, in either order, write at most once', () async {
      final discardedFirst = await previewed();
      ok(await w.imports.discard(discardedFirst.id));
      refused(await w.commit(discardedFirst.id, 5), 409);
      expect(w.records(), isEmpty);
      final committedFirst = await previewed();
      ok(await w.commit(committedFirst.id, 5));
      refused(await w.imports.discard(committedFirst.id), 409);
      expect(
        ok(await w.imports.get(committedFirst.id)).state,
        wire.ImportSessionState.IMPORT_SESSION_STATE_COMMITTED,
      );
      expect(w.records(), hasLength(5));
    });
  });

  group('a phase fails', () {
    test(
      'a row the ledger refuses, at any row, is named by rule and row and writes nothing',
      () async {
        for (var at = 1; at <= 5; at++) {
          final s = await previewed();
          final faulty = w.workflow(
            faults: ImportFaults(
              beforeRow: (row) {
                if (row == at) throw const Refusal.invalid('5.15', "Refused 'SKLEP A TESTOWY'");
              },
            ),
          );
          final error = refused(
            await faulty.commit(s.id, wire.CommitImportSessionRequest(confirmedAcceptedRows: 5)),
            409,
          );
          assertRule(error, 'The statement was rejected at row $at (commit.row_refused).');
          expect(error.message.contains('SKLEP'), isFalse);
          await assertStillOpenAndEmpty(s.id);
          expect(ok(await w.commit(s.id, 5)).committedWritten, 5, reason: 'retry after row $at');
          expect(w.records(), hasLength(5));
          expect(await w.net(erste), Erste.baseNet);
          for (final r in w.records().keys) {
            ok(await w.ledger.deleteRecord(r));
          }
        }
      },
    );

    test('a crash inside the ledger batch leaves all of it or none, and the retry writes the '
        'statement once', () async {
      final landed = <bool>[];
      for (var stopAfter = 0; stopAfter < 3; stopAfter++) {
        final s = await previewed();
        // jZen's test hook: the batch stops after `stopAfter` files are replaced, as power loss
        // would. Reopening finishes a journaled batch or leaves every file as it was.
        await w.reopen(
          afterFileReplaced: (replaced, total) async {
            if (replaced > stopAfter) throw StateError('power lost after $replaced of $total');
          },
        );
        final crashed = await w.commit(s.id, 5).then<Object?>((r) => r, onError: (Object e) => e);
        expect(crashed, isNot(isA<ZenSuccess<Object?>>()));
        await w.reopen();
        final read = ok(await w.imports.get(s.id));
        final records = w.records();
        landed.add(read.state == wire.ImportSessionState.IMPORT_SESSION_STATE_COMMITTED);
        if (landed.last) {
          expect(records, hasLength(5), reason: 'the batch landed whole');
          expect((read.committedWritten, read.committedAlreadyImported), (5, 0));
        } else {
          expect(records, isEmpty, reason: 'the batch did not land at all');
          expect(ok(await w.commit(s.id, 5)).committedWritten, 5);
        }
        expect(w.records(), hasLength(5));
        expect(await w.net(erste), Erste.baseNet);
        for (final r in w.records().keys) {
          ok(await w.ledger.deleteRecord(r));
        }
      }
      // jZen's hook stops a batch after its journal is saved, so every stop here is finished by the
      // reopening and the session is completed by what the ledger then holds. A batch that never
      // reached its journal leaves the plan unmatched: the last test of this group.
      expect(landed, everyElement(isTrue));
    });

    test('a crash between the ledger write and the session write is completed at the next '
        'launch, and an included duplicate is written once', () async {
      ok(await w.commit((await previewed()).id, 5));
      final again = await previewed();
      ok(await w.row(again.id, 1, include: true));
      final dying = w.workflow(
        faults: ImportFaults(afterLedgerWrite: () async => throw const _ProcessEnded()),
      );
      await expectLater(
        dying.commit(again.id, wire.CommitImportSessionRequest(confirmedAcceptedRows: 1)),
        throwsA(isA<_ProcessEnded>()),
      );
      expect(w.records(), hasLength(6), reason: 'the batch was written');
      expect(ok(w.sessions.sessions.get(again.id)).hasCommitPlan(), isTrue);

      await w.reopen();
      final read = ok(await w.imports.get(again.id));
      expect(read.state, wire.ImportSessionState.IMPORT_SESSION_STATE_COMMITTED);
      expect((read.committedWritten, read.committedAlreadyImported), (1, 0));
      // A retry answers the stored counts and writes nothing: the forced row is there once.
      expect(ok(await w.commit(again.id, 1)).committedWritten, 1);
      final row1 = w.records().values.where((r) => r.posting.amountMinor == Int64(-710));
      expect(row1.map((r) => r.importKey.occurrence).toList()..sort(), [1, 2]);
      expect(w.records(), hasLength(6));
    });

    test('a plan whose records are not all in the ledger is dropped, and nothing is counted '
        'that was not written', () async {
      final s = await previewed();
      // As a crash after the plan and before the batch leaves it.
      final planned = ok(w.sessions.sessions.get(s.id)).deepCopy()
        ..commitPlan = CommitPlan(recordIds: [w.store.newId()], written: 1);
      ok(await w.sessions.put(planned));
      await w.reopen();
      ok(await w.imports.expireDue());
      final kept = ok(w.sessions.sessions.get(s.id));
      expect(kept.hasCommitPlan(), isFalse);
      expect(kept.phase, ImportPhase.IMPORT_PHASE_PREVIEWED);
      expect(ok(await w.commit(s.id, 5)).committedWritten, 5);
    });
  });
}

/// The process ending, thrown where a crash would stop it.
final class _ProcessEnded implements Exception {
  const _ProcessEnded();
}
