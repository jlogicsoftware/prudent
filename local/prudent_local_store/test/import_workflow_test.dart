// Unit 8b (ADR-114): the import workflow on one device, rule for rule against the server's
// ImportSessionResourceTest, ImportDestinationTest, ImportCommitTest, ImportDuplicateDetectionTest
// and ImportBoundsTest — phase-0 §0.3 rows 8.1–8.5 and 8.10–8.24. Real encrypted stores, a clock
// the test moves, synthetic statements only (ADR-088).
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';
import 'package:prudent_local_store/prudent_local_store.dart';
import 'package:prudent_proto/generated/prudent/v1/accounts.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/categories.pb.dart' as wire;
import 'package:prudent_proto/generated/prudent/v1/imports.pb.dart' as wire;
import 'package:test/test.dart';

import 'support/imports.dart';

const parsedState = wire.ImportSessionState.IMPORT_SESSION_STATE_PARSED;
const previewedState = wire.ImportSessionState.IMPORT_SESSION_STATE_PREVIEWED;
const committedState = wire.ImportSessionState.IMPORT_SESSION_STATE_COMMITTED;
const discardedState = wire.ImportSessionState.IMPORT_SESSION_STATE_DISCARDED;
const expiredState = wire.ImportSessionState.IMPORT_SESSION_STATE_EXPIRED;
const accepted = wire.ImportRowStatus.IMPORT_ROW_STATUS_ACCEPTED;
const duplicate = wire.ImportRowStatus.IMPORT_ROW_STATUS_DUPLICATE;

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

  group('parse (rows 8.1, 8.2, 8.4, 8.21, 8.25)', () {
    test('opens a PARSED session holding the normalised rows and nothing else', () async {
      final s = ok(await w.upload(Erste.base(), account: erste));
      expect(s.state, parsedState);
      expect(s.formatId, 'erste-pl-csv');
      expect(s.currency, 'PLN');
      expect(s.accountId, erste);
      expect((s.acceptedRows, s.duplicateRows, s.rejectedRows), (5, 0, 0));
      expect(s.rows.map((r) => r.rowNumber), [1, 2, 3, 4, 5]);
      expect(s.rows.map((r) => r.amountMinor.toInt()), [-710, -2500, 10000, -300, -100]);
      expect(s.rows[2].hintCode, 'transfer.own_account');
      expect(
        s.expiresAtMs.toInt() - s.createdAtMs.toInt(),
        const Duration(hours: 24).inMilliseconds,
      );
      expect(w.records(), isEmpty, reason: 'a parse writes nothing to the ledger');
    });

    test('an unknown format is refused without echoing it, and nothing is written', () async {
      final before = w.snapshot();
      final error = refused(
        await w.imports.create(
          wire.CreateImportSessionRequest(formatId: 'mbank-SECRET', content: Erste.base()),
        ),
        400,
      );
      expect(error.message, 'Unsupported import format. Supported formats: erste-pl-csv.');
      expect(w.snapshot(), before);
    });

    test(
      'an empty upload and a malformed or unknown account are refused, nothing written',
      () async {
        final before = w.snapshot();
        expect(
          refused(await w.upload(Uint8List(0)), 400).message,
          'The statement was rejected (statement.empty_upload).',
        );
        expect(
          refused(await w.upload(Erste.base(), account: 'not-an-id'), 400).message,
          isNot(contains('not-an-id')),
        );
        expect(
          refused(await w.upload(Erste.base(), account: 'f' * 32), 400).message,
          'The statement was rejected (account.not_found).',
        );
        expect(w.snapshot(), before);
      },
    );

    test(
      'the statement is never kept: the session holds rows and an identity digest only',
      () async {
        final s = ok(await w.upload(Erste.base(), account: erste));
        final stored = ok(w.store.importSessions.get(s.id));
        expect(stored.statementIdentity, matches(RegExp(r'^[0-9a-f]{64}$')));
        final bytes = stored.writeToBuffer();
        // The summary row's owner and the statement's own account number appear nowhere.
        for (final secret in ['JAN TESTOWY', '00 0000 0000 0000 0000 0000 0001', Erste.account]) {
          expect(String.fromCharCodes(bytes).contains(secret), isFalse, reason: secret);
        }
      },
    );

    test('at most ten open sessions; ended and overdue ones do not count (row 8.4)', () async {
      final ids = <String>[];
      for (var i = 0; i < 10; i++) {
        ids.add(ok(await w.upload(Erste.base())).id);
      }
      final before = w.snapshot();
      expect(refused(await w.upload(Erste.base()), 409).message, contains('Too many'));
      expect(w.snapshot(), before);
      ok(await w.imports.discard(ids.first));
      ok(await w.upload(Erste.base()));
      w.nowMs += const Duration(hours: 24).inMilliseconds;
      ok(await w.upload(Erste.base()));
    });
  });

  group('the destination (row 8.5)', () {
    test(
      'parse into an account that is not the statement\'s is refused, nothing written',
      () async {
        final otherNumber = await w.account(number: Erste.otherAccount, name: 'Other');
        final unnumbered = await w.account(number: null, name: 'Cash');
        final inactive = await w.account(number: null, active: false, name: 'Old');
        final euro = await w.account(number: null, currencies: ['EUR'], name: 'Euro');
        final before = w.snapshot();
        expect(
          refused(await w.upload(Erste.base(), account: otherNumber), 400).message,
          'The statement was rejected (account.identity_mismatch).',
        );
        expect(
          refused(await w.upload(Erste.base(), account: unnumbered), 400).message,
          'The statement was rejected (account.number_missing).',
        );
        expect(
          refused(await w.upload(Erste.base(), account: inactive), 400).message,
          'The destination account is inactive.',
        );
        expect(
          refused(await w.upload(Erste.base(), account: euro), 400).message,
          'The destination account does not hold PLN. Add the currency to it first.',
        );
        expect(w.snapshot(), before);
      },
    );

    test('a destination chosen at preview is checked like the first choice, and the session '
        'stays as it was', () async {
      final otherNumber = await w.account(number: Erste.otherAccount, name: 'Other');
      final s = ok(await w.upload(Erste.base()));
      final before = w.snapshot();
      refused(await w.preview(s.id, account: otherNumber), 400);
      refused(await w.preview(s.id, account: 'f' * 32), 400);
      expect(w.snapshot(), before);
      final kept = ok(await w.imports.get(s.id));
      expect(kept.state, parsedState);
      expect(kept.hasAccountId(), isFalse);
      expect(ok(await w.preview(s.id, account: erste)).accountId, erste);
    });

    test('the commit checks the destination again (409), and nothing is written', () async {
      final s = await previewed();
      final before = w.records();
      ok(
        await w.ledger.updateAccount(
          erste,
          wire.UpdateAccountRequest(
            name: 'Erste',
            type: wire.AccountType.ACCOUNT_TYPE_CHECKING,
            isActive: true,
            accountNumber: Erste.otherAccount,
            balances: [wire.CurrencyBalance(currency: 'PLN', amountMinor: Int64.ZERO)],
          ),
        ),
      );
      expect(
        refused(await w.commit(s.id, 5), 409).message,
        'The statement was rejected (account.identity_mismatch).',
      );
      expect(w.records(), before);
      expect(ok(await w.imports.get(s.id)).state, previewedState);
    });

    test('the statement identity is kept while open and cleared when the session ends', () async {
      final s = await previewed();
      expect(ok(w.store.importSessions.get(s.id)).hasStatementIdentity(), isTrue);
      ok(await w.commit(s.id, 5));
      final ended = ok(w.store.importSessions.get(s.id));
      expect(ended.hasStatementIdentity(), isFalse);
      expect(ended.rows, isEmpty);
      expect(ended.hasDefaultExpenseCategoryId() || ended.hasDefaultIncomeCategoryId(), isFalse);
    });
  });

  group('the phases (row 8.1)', () {
    test('commit before a preview is a 409 and writes nothing', () async {
      final s = ok(await w.upload(Erste.base(), account: erste));
      final before = w.snapshot();
      expect(refused(await w.commit(s.id, 5), 409).message, contains('Preview'));
      expect(w.snapshot(), before);
    });

    test('an unknown or malformed session is a 404 everywhere', () async {
      for (final id in ['f' * 32, 'nope']) {
        refused(await w.imports.get(id), 404);
        refused(await w.preview(id), 404);
        refused(await w.commit(id, 1), 404);
        refused(await w.imports.discard(id), 404);
        refused(await w.defaults(id, expense: spending), 404);
        refused(await w.row(id, 1, note: 'x'), 404);
      }
    });

    test('a preview may be repeated while open; a commit ends the session for good', () async {
      final s = await previewed();
      expect(ok(await w.preview(s.id)).state, previewedState);
      final done = ok(await w.commit(s.id, 5));
      expect(done.state, committedState);
      expect(done.rows, isEmpty, reason: 'the commit answers counts only');
      expect((done.committedWritten, done.committedAlreadyImported), (5, 0));
      final before = w.snapshot();
      refused(await w.preview(s.id), 409);
      refused(await w.defaults(s.id, expense: spending), 409);
      refused(await w.row(s.id, 1, note: 'x'), 409);
      refused(await w.imports.discard(s.id), 409);
      expect(w.snapshot(), before);
    });

    test('discard ends the session and deletes its rows; it cannot then be committed', () async {
      final s = await previewed();
      final d = ok(await w.imports.discard(s.id));
      expect(d.state, discardedState);
      expect(ok(w.store.importSessions.get(s.id)).rows, isEmpty);
      refused(await w.commit(s.id, 5), 409);
      expect(w.records(), isEmpty);
    });
  });

  group('expiry (rows 8.3, 8.19)', () {
    test('an overdue session cannot be previewed or committed, and a read ends it', () async {
      final s = await previewed();
      w.nowMs += const Duration(hours: 24).inMilliseconds;
      final before = w.snapshot();
      expect(refused(await w.commit(s.id, 5), 409).message, contains('expired'));
      refused(await w.preview(s.id), 409);
      expect(w.snapshot(), before);
      final read = ok(await w.imports.get(s.id));
      expect(read.state, expiredState);
      expect(read.rows, isEmpty);
      expect(ok(w.store.importSessions.get(s.id)).rows, isEmpty);
    });

    test('the sweep expires only due sessions and deletes their rows', () async {
      final old = ok(await w.upload(Erste.base()));
      w.nowMs += const Duration(hours: 12).inMilliseconds;
      final fresh = ok(await w.upload(Erste.base()));
      w.nowMs += const Duration(hours: 12).inMilliseconds;
      expect(ok(await w.imports.expireDue()), 1);
      expect(ok(w.store.importSessions.get(old.id)).rows, isEmpty);
      expect(ok(w.store.importSessions.get(fresh.id)).rows, hasLength(5));
      expect(ok(await w.imports.expireDue()), 0);
    });
  });

  group('the list (row 8.24)', () {
    test('newest first, without rows, narrowed by an exact state, limit 1 to 100', () async {
      final first = ok(await w.upload(Erste.base()));
      w.nowMs += 1000;
      final second = ok(await w.upload(Erste.base()));
      ok(await w.imports.discard(first.id));
      final all = ok(await w.imports.list());
      expect(all.sessions.map((s) => s.id), [second.id, first.id]);
      expect(all.sessions.every((s) => s.rows.isEmpty), isTrue);
      expect(ok(await w.imports.list(state: 'DISCARDED')).sessions.map((s) => s.id), [first.id]);
      expect(ok(await w.imports.list(limit: 1)).sessions, hasLength(1));
      refused(await w.imports.list(state: 'discarded'), 400);
      refused(await w.imports.list(limit: 0), 400);
      refused(await w.imports.list(limit: 101), 400);
    });
  });

  group('row decisions and defaults (rows 8.12, 8.13)', () {
    test('a row category must exist, be active and suit the direction; empty clears it', () async {
      final s = await previewed();
      refused(await w.row(s.id, 1, category: 'f' * 32), 400);
      refused(await w.row(s.id, 1, category: 'bad'), 400);
      refused(await w.row(s.id, 1, category: income), 400);
      ok(await w.ledger.archiveCategory(other));
      refused(await w.row(s.id, 1, category: other), 409);
      ok(await w.ledger.restoreCategory(other));
      final set = ok(await w.row(s.id, 1, category: other));
      expect(set.row.categoryId, other);
      expect((set.acceptedRows, set.duplicateRows, set.rejectedRows), (5, 0, 0));
      expect(ok(await w.row(s.id, 1, category: '')).row.hasCategoryId(), isFalse);
      refused(await w.row(s.id, 9, note: 'x'), 404);
    });

    test('a note is trimmed, at most 500 characters (code points), and empty clears it', () async {
      final s = await previewed();
      final emoji = '😀' * 500;
      expect(ok(await w.row(s.id, 1, note: '  $emoji  ')).row.note, emoji);
      refused(await w.row(s.id, 1, note: '$emoji!'), 400);
      expect(ok(await w.row(s.id, 1, note: '   ')).row.hasNote(), isFalse);
    });

    test('defaults file every row without its own category, by the sign of its amount', () async {
      final s = ok(await w.upload(Erste.base(), account: erste));
      ok(await w.preview(s.id));
      refused(await w.defaults(s.id, expense: income), 400);
      refused(await w.defaults(s.id, income: spending), 400);
      ok(await w.defaults(s.id, expense: spending, income: income));
      ok(await w.row(s.id, 2, category: other));
      ok(await w.commit(s.id, 5));
      final byAmount = {for (final r in w.records().values) r.posting.amountMinor.toInt(): r};
      expect(byAmount[-710]!.categoryId, spending);
      expect(byAmount[-2500]!.categoryId, other);
      expect(byAmount[10000]!.categoryId, income);
    });

    test('a commit with a row that has neither a category nor a default is refused', () async {
      final s = ok(await w.upload(Erste.base(), account: erste));
      ok(await w.preview(s.id));
      ok(await w.defaults(s.id, expense: spending));
      final before = w.snapshot();
      expect(
        refused(await w.commit(s.id, 5), 409).message,
        startsWith('1 row(s) have no category'),
      );
      expect(w.snapshot(), before);
    });
  });

  group('the commit (rows 8.11, 8.14–8.17)', () {
    test('one ordinary record per row, with its key and an id derived from it', () async {
      final s = await previewed();
      final done = ok(await w.commit(s.id, 5));
      expect((done.committedWritten, done.committedAlreadyImported), (5, 0));
      final records = w.records().values.toList();
      expect(records, hasLength(5));
      for (final r in records) {
        expect(r.posting.accountId, erste);
        expect(r.posting.currency, 'PLN');
        expect(r.hasImportKey(), isTrue);
        expect(r.id, DerivedIds.imported(erste, r.importKey.fingerprint, r.importKey.occurrence));
        expect(r.hasCorrection() || r.hasPlanLink(), isFalse);
      }
      final transfer = records.firstWhere((r) => r.posting.amountMinor == Int64(10000));
      expect(transfer.title, 'Przelew na rachunek własny');
      // The holder's own name and address are not carried (ADR-090); a BLIK payee is.
      expect(transfer.hasPayee(), isFalse);
      final blik = records.firstWhere((r) => r.posting.amountMinor == Int64(-2500));
      expect(blik.payee, 'SKLEP B TESTOWY');
      expect(await w.net(erste), Erste.baseNet);
      expect(
        ok(w.store.transfers.list()),
        isEmpty,
        reason: 'an own-account transfer is a plain record',
      );
    });

    test('the confirmed count must match, and a repeat answers the stored counts', () async {
      final s = await previewed();
      final before = w.snapshot();
      expect(refused(await w.commit(s.id, 4), 409).message, contains('does not match'));
      expect(w.snapshot(), before);
      ok(await w.commit(s.id, 5));
      final after = w.snapshot();
      final again = ok(await w.commit(s.id, 5));
      expect((again.committedWritten, again.committedAlreadyImported), (5, 0));
      expect(refused(await w.commit(s.id, 4), 409).message, contains('different number'));
      expect(w.snapshot(), after);
    });

    test('a statement imported in full commits with nothing written', () async {
      ok(await w.commit((await previewed()).id, 5));
      final again = await previewed();
      expect((again.acceptedRows, again.duplicateRows), (0, 5));
      expect(again.rows.every((r) => r.status == duplicate), isTrue);
      expect(again.rows.every((r) => r.duplicateCode == 'duplicate.already_imported'), isTrue);
      final done = ok(await w.commit(again.id, 0));
      expect((done.committedWritten, done.committedAlreadyImported), (0, 0));
      expect(w.records(), hasLength(5));
      expect(await w.net(erste), Erste.baseNet);
    });

    test(
      'two sessions of one file previewed before either commits write the ledger once',
      () async {
        final a = await previewed();
        final b = await previewed();
        ok(await w.commit(a.id, 5));
        final second = ok(await w.commit(b.id, 5));
        expect((second.committedWritten, second.committedAlreadyImported), (0, 5));
        expect(w.records(), hasLength(5));
        expect(await w.net(erste), Erste.baseNet);
      },
    );
  });

  group('duplicates (rows 8.10, 8.11)', () {
    test('identical rows in one statement are both imported, and neither again', () async {
      final card = ErsteStatements.card('06-03-2026', '06-03-2026', 'SKLEP TESTOWY', '-1,00', 1);
      final twin = ErsteStatements.card('06-03-2026', '06-03-2026', 'SKLEP TESTOWY', '-1,00', 2);
      final file = Erste.withRows([card, twin]);
      final first = await w.previewed(file, account: erste, expense: spending, income: income);
      expect(first.acceptedRows, 2);
      ok(await w.commit(first.id, 2));
      final occurrences = w.records().values.map((r) => r.importKey.occurrence).toList()..sort();
      expect(occurrences, [1, 2]);
      final again = await w.previewed(file, account: erste, expense: spending, income: income);
      expect((again.acceptedRows, again.duplicateRows), (0, 2));
    });

    test(
      'an included duplicate takes the next free occurrence; the decision counts as accepted',
      () async {
        ok(await w.commit((await previewed()).id, 5));
        final again = await previewed();
        final included = ok(await w.row(again.id, 1, include: true));
        expect((included.acceptedRows, included.duplicateRows), (1, 4));
        final done = ok(await w.commit(again.id, 1));
        expect((done.committedWritten, done.committedAlreadyImported), (1, 0));
        final row1 = w.records().values.where((r) => r.posting.amountMinor == Int64(-710)).toList();
        expect(row1.map((r) => r.importKey.occurrence).toList()..sort(), [1, 2]);
        // A third session including it again steps over both.
        final third = await previewed();
        ok(await w.row(third.id, 1, include: true));
        ok(await w.commit(third.id, 1));
        final now = w.records().values.where((r) => r.posting.amountMinor == Int64(-710));
        expect(now.map((r) => r.importKey.occurrence).toList()..sort(), [1, 2, 3]);
      },
    );

    test('including a row that is not a duplicate, or a rejected row, is refused', () async {
      final s = await previewed();
      expect(refused(await w.row(s.id, 1, include: true), 400).message, contains('row 1'));
      final flagged = await w.previewed(
        Erste.withField(3, 5, '-100,00'),
        account: erste,
        expense: spending,
        income: income,
      );
      expect(refused(await w.row(flagged.id, 3, note: 'x'), 409).message, contains('Row 3'));
    });

    test('a new preview clears the include decision', () async {
      ok(await w.commit((await previewed()).id, 5));
      final again = await previewed();
      ok(await w.row(again.id, 1, include: true));
      final shown = ok(await w.preview(again.id));
      expect((shown.acceptedRows, shown.duplicateRows), (0, 5));
      expect(shown.rows.every((r) => !r.includeDuplicate), isTrue);
    });

    test(
      'a deleted imported record is offered again; a record typed by hand is no duplicate',
      () async {
        ok(await w.commit((await previewed()).id, 5));
        final row1 = w.records().values.firstWhere((r) => r.posting.amountMinor == Int64(-710));
        ok(await w.ledger.deleteRecord(row1.id));
        final again = await previewed();
        expect(again.rows.where((r) => r.status == accepted).map((r) => r.rowNumber), [1]);
        ok(await w.commit(again.id, 1));
        expect(await w.net(erste), Erste.baseNet);
      },
    );

    test('rows are not marked without a destination, and a preview for another account starts '
        'from scratch', () async {
      ok(await w.commit((await previewed()).id, 5));
      final s = ok(await w.upload(Erste.base()));
      expect(s.rows.every((r) => r.status == accepted), isTrue);
      expect(ok(await w.preview(s.id, account: erste)).duplicateRows, 5);
      // The statement's number moves to a second account, which holds nothing of it.
      await w.renumber(erste, Erste.otherAccount);
      final second = await w.account(name: 'Second');
      final forSecond = ok(await w.preview(s.id, account: second));
      expect((forSecond.acceptedRows, forSecond.duplicateRows), (5, 0));
      expect(forSecond.rows.every((r) => r.duplicateCode.isEmpty), isTrue);
      await w.renumber(second, null);
      await w.renumber(erste, Erste.account);
      expect(ok(await w.preview(s.id, account: erste)).duplicateRows, 5);
    });

    test('the wire carries the reason, never the key', () async {
      ok(await w.commit((await previewed()).id, 5));
      final again = await previewed();
      final text = again.toString();
      for (final r in w.records().values) {
        expect(text.contains(r.importKey.fingerprint), isFalse);
      }
    });
  });
}
