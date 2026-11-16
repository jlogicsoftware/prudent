// Unit 8b (ADR-114): the server's ImportFailureMatrixTest on Local. Every case of the server's
// ImportFailureCatalogue — each malformed, drifted, mixed-currency, oversized and misdirected
// statement, and each statement that is accepted with rows flagged — is uploaded through the
// session workflow, from test/golden/erste_import.json, which the server's JVM wrote (unit 8a).
//
// A refused statement must name its rule and rows in the server's words, leave every record,
// session and account exactly as they were, and quote no statement text. An accepted one must list
// each row as the server does, and its commit must write exactly the accepted rows, with the keys
// the server computes, and nothing of a flagged row.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';
import 'package:prudent_local_core/prudent_local_core.dart';
import 'package:prudent_local_store/prudent_local_store.dart';
import 'package:prudent_proto/generated/prudent/v1/imports.pb.dart' as wire;
import 'package:test/test.dart';

import 'support/imports.dart';

void main() {
  final file = jsonDecode(
    File('../prudent_local_core/test/golden/erste_import.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final cases = (file['cases']! as List<Object?>).cast<Map<String, Object?>>();
  // The account id the server keyed every golden fingerprint with, in Local's form.
  final keyedAccount = LocalIds.fromServerId(file['fingerprintAccountId']! as String);

  late ImportWorld w;
  late String anything;
  setUp(() async {
    w = await ImportWorld.create();
    anything = await w.category('Anything');
  });
  tearDown(() => w.dispose());

  /// The destination a case uploads into: none, or an active PLN account holding [number] — for
  /// the statement's own number, the one with the server's fingerprint account id.
  Future<String?> destination(Map<String, Object?> entry) async {
    if (entry['checkDestination'] != true) return null;
    final number = entry['destination'] as String?;
    if (number == Erste.account) {
      ok(
        await w.store.putAccount(
          Account(
            id: keyedAccount,
            name: 'Erste',
            kind: AccountKind.ACCOUNT_KIND_CHECKING,
            active: true,
            accountNumber: number,
          ),
        ),
      );
      ok(
        await w.store.putAccountCurrency(
          AccountCurrency(
            id: DerivedIds.accountCurrency(keyedAccount, 'PLN'),
            accountId: keyedAccount,
            currency: 'PLN',
            openingMinor: Int64.ZERO,
          ),
        ),
      );
      return keyedAccount;
    }
    return w.account(number: number == null || number.isEmpty ? null : number);
  }

  String expectedMessage(Map<String, Object?> outcome) => ImportRejection.rows(
    outcome['rule']! as String,
    (outcome['rows']! as List<Object?>).cast<int>(),
    outcome['total']! as int,
  ).message;

  group('every catalogue case answers through the session workflow as the server does', () {
    for (final entry in cases) {
      test('${entry['source']}: ${entry['name']}', () async {
        final content = ErsteStatements.rebuild(entry['content']);
        final today = entry['today']! as String;
        w.nowMs = DateTime.parse('${today}T12:00:00Z').millisecondsSinceEpoch;
        final account = await destination(entry);
        final outcome = entry['outcome']! as Map<String, Object?>;
        final before = w.snapshot();

        final answer = await w.upload(content, account: account);

        if (outcome.containsKey('rule')) {
          final rows = outcome['rows']! as List<Object?>;
          final error = refused(answer, 400);
          expect(
            error.message,
            rows.isEmpty
                ? 'The statement was rejected (${outcome['rule']}).'
                : expectedMessage(outcome),
          );
          expect(w.snapshot(), before, reason: 'a refused statement writes nothing');
          _assertNoStatementText(content, '${error.message} $error ${error.internalData}');
          return;
        }

        final session = ok(answer);
        final wanted = (outcome['rows']! as List<Object?>).cast<Map<String, Object?>>();
        expect(session.rows, hasLength(wanted.length));
        for (var i = 0; i < wanted.length; i++) {
          final want = wanted[i];
          final row = session.rows[i];
          expect(row.rowNumber, want['row']);
          if (want.containsKey('rejection')) {
            expect(row.status, wire.ImportRowStatus.IMPORT_ROW_STATUS_REJECTED);
            expect(row.rejectionCode, want['rejection']);
            expect(row.hasDescription() || row.hasAmountMinor(), isFalse);
          } else {
            expect(row.status, wire.ImportRowStatus.IMPORT_ROW_STATUS_ACCEPTED);
            expect(row.amountMinor.toString(), want['amount']);
            expect(row.transactionDate, want['date']);
            expect(row.hasDescription() ? row.description : null, want['description']);
            expect(row.hintCode.isEmpty ? null : row.hintCode, want['hint']);
          }
        }
        if (account == null) return; // A fixture uploaded with no destination: parse only.

        final shown = ok(await w.preview(session.id));
        ok(await w.defaults(session.id, expense: anything, income: anything));
        if (account == keyedAccount) {
          // The keys the server computes for this statement in this account, row for row.
          final stored = ok(w.store.importSessions.get(session.id));
          final keys = [
            for (final row in stored.rows)
              if (row.hasFingerprint()) [row.fingerprint, row.occurrence],
          ];
          expect(keys, outcome['keys']);
        }
        final writable = shown.acceptedRows;
        final done = ok(await w.commit(session.id, writable));
        expect((done.committedWritten, done.committedAlreadyImported), (writable, 0));
        expect(done.rows, isEmpty);
        final written = w.records().values.toList();
        expect(written, hasLength(writable));
        final acceptedAmounts = [
          for (final want in wanted)
            if (!want.containsKey('rejection')) want['amount'],
        ]..sort();
        expect(
          written.map((r) => r.posting.amountMinor.toString()).toList()..sort(),
          acceptedAmounts,
        );
        expect(ok(w.store.importSessions.get(session.id)).rows, isEmpty);
      });
    }
  });

  group('the workflow cases the golden file names', () {
    final named = (file['workflowCases']! as List<Object?>).cast<String>();

    Future<void> refusedWritingNothing(String? account, String message) async {
      final before = w.snapshot();
      final error = refused(await w.upload(Erste.base(), account: account), 400);
      expect(error.message, message);
      expect(w.snapshot(), before);
      _assertNoStatementText(Erste.base(), error.message);
    }

    test(named[0], () async {
      final euro = await w.account(currencies: ['EUR']);
      await refusedWritingNothing(
        euro,
        'The destination account does not hold PLN. Add the currency to it first.',
      );
    });
    test(named[1], () async {
      await refusedWritingNothing(
        await w.account(active: false),
        'The destination account is inactive.',
      );
    });
    // There is one person per Local store (phase-0 §0.3 X.1): another user's account is an id this
    // store does not hold, answered as the server answers one.
    for (final name in named.skip(2)) {
      test(name, () async {
        expect(name, endsWith('account.not_found'));
        await refusedWritingNothing(
          w.store.newId(),
          'The statement was rejected (account.not_found).',
        );
      });
    }
  });

  group('the matrix\'s own cases', () {
    late String erste;
    setUp(() async => erste = await w.account());

    test('a statement of only flagged rows previews and commits as nothing', () async {
      final file = Erste.withRows([
        ErsteStatements.tx('06-03-2026', '06-03-2026', 'CARD PAYMENT TEST', '', '', '-1,00', 1),
        ErsteStatements.tx('06-03-2026', '06-03-2026', 'Odsetki TEST', '', '', '-2,00', 2),
      ]);
      final s = await w.previewed(file, account: erste, expense: anything, income: anything);
      expect((s.acceptedRows, s.rejectedRows), (0, 2));
      final done = ok(await w.commit(s.id, 0));
      expect((done.committedWritten, done.committedAlreadyImported), (0, 0));
      expect(w.records(), isEmpty);
    });

    test(
      'a benign variation (every field quoted) is the same statement, not a false alarm',
      () async {
        final plain = await w.previewed(
          Erste.base(),
          account: erste,
          expense: anything,
          income: anything,
        );
        ok(await w.commit(plain.id, 5));
        final quoted = cases.firstWhere(
          (c) => (c['name']! as String).startsWith('every field quoted'),
        );
        final again = await w.previewed(
          ErsteStatements.rebuild(quoted['content']),
          account: erste,
          expense: anything,
          income: anything,
        );
        expect((again.acceptedRows, again.duplicateRows), (0, 5));
      },
    );

    test('overlapping statements with other sequence numbers write each operation once', () async {
      final rows = Erste.baseRows().skip(1).toList();
      final first = Erste.withRows(rows.sublist(0, 3));
      // The second export starts one row earlier in the first one's terms, numbered afresh.
      final renumbered = [
        for (var i = 1; i < rows.length; i++) [...rows[i]]..[7] = '${10 + i}',
      ];
      final second = Erste.withRows(renumbered);
      ok(
        await w.commit(
          (await w.previewed(first, account: erste, expense: anything, income: anything)).id,
          3,
        ),
      );
      final s = await w.previewed(second, account: erste, expense: anything, income: anything);
      expect((s.acceptedRows, s.duplicateRows), (2, 2));
      ok(await w.commit(s.id, 2));
      expect(await w.net(erste), Erste.baseNet);
    });

    test('a commit repeated after a lost answer answers the same and writes nothing', () async {
      final s = await w.previewed(
        Erste.base(),
        account: erste,
        expense: anything,
        income: anything,
      );
      final first = ok(await w.commit(s.id, 5));
      final after = w.snapshot();
      final again = ok(await w.commit(s.id, 5));
      expect(again, first);
      expect(w.snapshot(), after);
    });
  });

  test('nothing in the import code writes a log line, so no statement text can reach one', () {
    for (final file in Directory('lib/src/imports').listSync().whereType<File>()) {
      final source = file.readAsStringSync();
      final logging = RegExp(
        r'\b(print|debugPrint|log)\(|\bstd(err|out)\b|\bLogger\b|dart:developer',
      );
      expect(logging.firstMatch(source)?.group(0), isNull, reason: file.path);
    }
  });

  test('the leak check fires on a statement value in any form', () {
    expect(
      () => _assertNoStatementText(Erste.base(), 'refused: SKLEP B TESTOWY'),
      throwsA(isA<TestFailure>()),
    );
    expect(
      () => _assertNoStatementText(Erste.base(), 'refused: 00000000000000000000000010'),
      throwsA(isA<TestFailure>()),
    );
    _assertNoStatementText(Erste.base(), 'The statement was rejected at row 3 (amount.invalid).');
  });
}

/// Fails when [answer] holds any text value of [content]: a description, a counterparty, a holder,
/// an account number with or without its spaces.
void _assertNoStatementText(List<int> content, String answer) {
  for (final text in Erste.texts(Uint8List.fromList(content))) {
    if (answer.contains(text)) fail('an answer quotes the statement: "$text"');
  }
}
