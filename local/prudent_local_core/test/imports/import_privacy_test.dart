// Unit 8a: no statement text reaches a refusal, an exception message, a toString or a log line.
//
// Every field of a synthetic statement carries a unique marker — the holder's name, the summary
// fields nobody reads, each merchant, counterparty and balance, and in the mutations below the very
// value that breaks the rule (a bad date, amount, sequence or account number). Each mutation is run
// through the whole parse stage with print captured, and every word that comes out is searched for
// every marker. The mutations between them reach every rule this package emits, so a new rule
// cannot be added without passing through here too.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:prudent_local_core/prudent_local_core.dart';
import 'package:test/test.dart';

import 'erste_support.dart';

const _marker = 'QZX';

/// A marker that can sit inside a field of the given shape without changing its meaning.
String _m(String what) => '$_marker$what$_marker';

List<String> _summary() => [
  '2026-11-14',
  '01-01-2026',
  "'00 0000 0000 0000 0000 0000 0001",
  _m('HOLDER NAME AND ADDRESS'),
  'PLN',
  _m('FIELD6'),
  _m('FIELD7'),
  _m('FIELD8'),
  '',
];

List<String> _card(String merchant, String amount, int sequence, {String date = '10-03-2026'}) =>
    ErsteStatements.card(date, date, _m(merchant), amount, sequence, balance: _m('BALANCE$sequence'));

List<String> _blik(String merchant, String amount, int sequence) => ErsteStatements.tx(
  '09-03-2026',
  '09-03-2026',
  'Zakup BLIK ${_m(merchant)} ref:00000000001',
  _m('COUNTERPARTY$sequence'),
  '00 0000 0000 0000 0000 0000 0010',
  amount,
  sequence,
  balance: _m('BALANCE$sequence'),
);

List<String> _own(String amount, int sequence, {String account = '00 0000 0000 0000 0000 0000 0002'}) =>
    ErsteStatements.tx(
      '08-03-2026',
      '08-03-2026',
      ErsteStatementImporter.ownTransferDescription,
      _m('OWN HOLDER ADDRESS'),
      account,
      amount,
      sequence,
      balance: _m('BALANCE$sequence'),
    );

/// The marked base statement: a card, a BLIK purchase, an own-account transfer, two more cards.
List<List<String>> _base() => [
  _summary(),
  _card('MERCHANT ONE', '-7,10', 1),
  _blik('MERCHANT TWO', '-25,00', 2),
  _own('100,00', 3),
  _card('MERCHANT FOUR', '-3,00', 4),
  _card('MERCHANT FIVE', '-1,00', 5),
];

Uint8List _with(void Function(List<List<String>> rows) change) {
  final rows = _base();
  change(rows);
  return ErsteStatements.bytes(rows);
}

Uint8List _text(String Function(String text) change) =>
    Uint8List.fromList(utf8.encode(change(utf8.decode(ErsteStatements.bytes(_base())))));

/// Each mutation and the rule it must end in (`null`: accepted, the rows flagged or not).
Map<String, (Uint8List, String?)> _mutations() {
  final base = ErsteStatements.bytes(_base());
  return {
    'the base statement': (base, null),
    'an empty upload': (Uint8List(0), ImportRule.emptyUpload),
    'over 5 MiB of marked text': (
      Uint8List.fromList(
        utf8.encode(_m('BIG') * (StatementBounds.maxContentBytes ~/ _m('BIG').length + 1)),
      ),
      ImportRule.tooLarge,
    ),
    'a byte-order mark': (Uint8List.fromList([0xEF, 0xBB, 0xBF, ...base]), ImportRule.encodingBom),
    'a NUL byte': (Uint8List.fromList([...base.sublist(0, 200), 0, ...base.sublist(200)]), ImportRule.encodingNulByte),
    'Latin-2 bytes': (Uint8List.fromList([...base.sublist(0, 200), 0xA3, ...base.sublist(200)]), ImportRule.encodingNotUtf8),
    'CRLF': (_text((t) => t.replaceAll('\n', '\r\n')), ImportRule.lineEnding),
    'no final newline': (_text((t) => t.substring(0, t.length - 1)), ImportRule.noFinalNewline),
    'a stray quote in a merchant': (_text((t) => t.replaceFirst('MERCHANT FOUR', 'MERCHANT "FOUR')), ImportRule.csvMalformed),
    'semicolons': (_text((t) => t.replaceAll(',', ';')), ImportRule.delimiter),
    'a header row': (_with((r) => r.insert(0, [...List.filled(8, _m('HEADER')), ''])), ImportRule.headerRow),
    'no summary row': (_with((r) => r.removeAt(0)), ImportRule.summaryMissing),
    'a positive card amount': (_with((r) => r[1][5] = '7,10'), ImportRule.amountColumn),
    'a marked tenth field': (_with((r) => r[2].add(_m('TENTH'))), ImportRule.fieldCount),
    'a marked trailing field': (_with((r) => r[2][8] = _m('TRAILING')), ImportRule.trailingField),
    'a marked export date': (_with((r) => r[0][0] = '2026-11-14${_m('EXPORT')}'), ImportRule.exportDateInvalid),
    'a marked period start': (_with((r) => r[0][1] = _m('PERIOD')), ImportRule.periodStartInvalid),
    'a marked account number': (_with((r) => r[0][2] = "'${_m('ACC-OUNT')}"), ImportRule.summaryAccountInvalid),
    'a marked currency': (_with((r) => r[0][4] = _m('CURRENCY')), ImportRule.currencyUnsupported),
    'a summary and nothing else': (_with((r) => r.removeRange(1, r.length)), ImportRule.statementEmpty),
    'a marked date': (_with((r) => r[2][1] = _m('DATE')), ImportRule.dateInvalid),
    'a date in 2099': (_with((r) => r[2][0] = r[2][1] = '10-03-2099'), ImportRule.dateOutOfRange),
    'a booking before the transaction': (_with((r) => r[2][0] = '01-03-2026'), ImportRule.bookingBeforeTransaction),
    'a marked amount': (_with((r) => r[2][5] = '-25,00${_m('AMOUNT')}'), ImportRule.amountInvalid),
    'a zero amount': (_with((r) => r[2][5] = '0,00'), ImportRule.amountZero),
    'a marked sequence number': (_with((r) => r[2][7] = _m('SEQUENCE')), ImportRule.sequenceInvalid),
    'a repeated sequence number': (_with((r) => r[3][7] = '2'), ImportRule.sequenceDuplicate),
    'a card payment in euros': (
      _with((r) => r[1][2] = 'DOP. MC 000000******0000 PŁATNOŚĆ KARTĄ 7.10 EUR ${_m('MERCHANT EURO')}'),
      ImportRule.cardForeignCurrency,
    ),
    'a marked description of no known shape': (_with((r) => r[2][2] = _m('UNKNOWN DESCRIPTION')), null),
    'an outgoing own-account transfer': (_with((r) => r[3][5] = '-100,00'), null),
    'a card amount that disagrees with its text': (_with((r) => r[1][5] = '-7,11'), null),
    'a marked counterparty account': (_with((r) => r[2][4] = _m('COUNTERPARTY ACCOUNT')), null),
    'an own-account transfer to the same account': (
      _with((r) => r[3] = _own('100,00', 3, account: '00 0000 0000 0000 0000 0000 0001')),
      null,
    ),
    'more rows than an import holds': (
      ErsteStatements.bytes([
        _summary(),
        for (var i = 1; i <= StatementBounds.defaultMaxRows + 1; i++) _card('MANY $i', '-1,00', i),
      ]),
      ImportRule.tooManyRows,
    ),
    'a marked counterparty over the field limit': (
      _with((r) => r[2][3] = _m('LONG') * (StatementBounds.maxFieldChars ~/ 4)),
      ImportRule.fieldTooLong,
    ),
  };
}

/// Every word the parse stage says about [content], with print captured: refusals, errors,
/// statement and row descriptions.
(List<String>, Set<String>) _say(Uint8List content, String? destination) {
  final said = <String>[];
  final rules = <String>{};
  runZoned(
    () {
      try {
        final statement = parseErsteStatement(content, today: CivilDate.parse('2026-11-16'));
        said.add('$statement');
        for (final row in statement.rows) {
          said.add('$row');
          if (row.isRejected) {
            expect(
              [row.description, row.counterparty, row.counterpartyAccount, row.externalId],
              everyElement(isNull),
              reason: 'a rejected row carries nothing',
            );
            rules.add(row.rejectionCode!);
          }
          if (row.hintCode != null) rules.add(row.hintCode!);
          if (!row.isRejected) {
            final fingerprint = RowFingerprints.fingerprint(
              '123e4567e89b42d3a456426614174000',
              ErsteStatementImporter.formatId,
              statement.currency,
              FingerprintFields(
                transactionDate: row.transactionDate!,
                amountMinor: row.amountMinor!,
                description: row.description,
                counterparty: row.counterparty,
                counterpartyAccount: row.counterpartyAccount,
              ),
            );
            said.add(fingerprint);
          }
        }
        ErsteStatementImporter.checkDestination(statement.accountIdentity, destination);
      } on ImportRejection catch (refused) {
        said
          ..add('$refused')
          ..add(refused.message);
        rules.add(refused.rule);
      } on Object catch (error) {
        // Anything else is a failure of its own, but its text is checked first.
        said.add('$error');
        rethrow;
      }
    },
    zoneSpecification: ZoneSpecification(print: (_, _, _, line) => said.add('print: $line')),
  );
  return (said, rules);
}

void main() {
  final reached = <String>{};

  group('no marker leaves the parse stage', () {
    for (final MapEntry(key: name, value: (content, rule)) in _mutations().entries) {
      test(name, () {
        final (said, rules) = _say(content, '00000000000000000000000001');
        for (final word in said) {
          expect(word, isNot(contains(_marker)), reason: 'statement text in "$word"');
        }
        if (rule != null) expect(rules, contains(rule));
        reached.addAll(rules);
      });
    }

    test('a destination with another number or none', () {
      for (final (destination, rule) in [
        ('00000000000000000000000009', ImportRule.identityMismatch),
        (null, ImportRule.numberMissing),
      ]) {
        final (said, rules) = _say(ErsteStatements.bytes(_base()), destination);
        for (final word in said) {
          expect(word, isNot(contains(_marker)));
        }
        expect(rules, contains(rule));
        reached.addAll(rules);
      }
      try {
        ErsteStatementImporter.checkDestination(null, '00000000000000000000000001');
      } on ImportRejection catch (refused) {
        reached.add(refused.rule);
      }
    });

    test('a stable-identifier format refuses a missing or repeated marked identifier', () {
      for (final ids in [
        [_m('ID'), null],
        [_m('ID'), _m('ID')],
      ]) {
        try {
          StatementBounds.validate(
            ErsteStatementImporter.formatId,
            ParsedStatement('PLN', [
              for (var i = 0; i < ids.length; i++)
                ParsedRow.accepted(
                  rowNumber: i + 1,
                  transactionDate: CivilDate.parse('2026-03-01'),
                  bookingDate: null,
                  amountMinor: -1,
                  description: _m('DESCRIPTION'),
                  counterparty: null,
                  counterpartyAccount: null,
                  externalId: ids[i],
                ),
            ], null),
            stableExternalId: true,
          );
          fail('accepted');
        } on ImportRejection catch (refused) {
          expect('$refused', isNot(contains(_marker)));
          reached.add(refused.rule);
        }
      }
    });

    test('between them the mutations reach every rule this package emits', () {
      expect(ImportRule.parseStage.difference(reached), isEmpty);
    });
  });

  test('a rule code that is not a code is refused without being quoted', () {
    for (final text in [_m('free text'), 'a.b ${_m('x')}', '${_m('X')}.y']) {
      expect(
        () => ImportRejection(text),
        throwsA(isA<ArgumentError>().having((e) => '$e', 'text', isNot(contains(_marker)))),
      );
    }
    expect(() => ImportRejection(ImportRule.dateInvalid, 0), throwsArgumentError);
    expect(() => ImportRejection.rows(ImportRule.dateInvalid, const [], 0), throwsArgumentError);
  });

  test('an importer bug names the format and never a row\'s text', () {
    final broken = ParsedStatement('PLN', [
      const ParsedRow.rejected(1, 'description.unknown_shape'),
      const ParsedRow.rejected(1, 'description.unknown_shape'),
    ], null);
    expect(
      () => StatementBounds.validate('erste-pl-csv', broken),
      throwsA(isA<StateError>().having((e) => '$e', 'text', contains("Importer 'erste-pl-csv'"))),
    );
  });
}
