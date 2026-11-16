// Unit 8a (ADR-088 to ADR-094): the Erste importer's parse stage, held to the server's by
// test/golden/erste_import.json — every case of the server's ImportFailureCatalogue that the parse
// stage decides, the synthetic fixtures, and the places Java's string semantics differ from Dart's.
// The last group mirrors the server's ImportRuleCatalogueTest: every rule the server can emit is
// named here, and every rule this package emits has a case that passed.
import 'dart:io';

import 'package:prudent_local_core/prudent_local_core.dart';
import 'package:test/test.dart';

import '../golden.dart';
import 'erste_support.dart';

void main() {
  final file = golden('erste_import.json');
  final today = CivilDate.parse(file['today']! as String);
  final fingerprintAccount = file['fingerprintAccountId']! as String;

  /// Every rule a passing case named: a refusal, a flagged row or a hint.
  final proven = <String>{};

  test('the constants are the server\'s', () {
    final limits = file['limits']! as Map<String, Object?>;
    expect(StatementBounds.maxContentBytes, limits['maxContentBytes']);
    expect(StatementBounds.defaultMaxRows, limits['maxRows']);
    expect(StatementBounds.maxFieldChars, limits['maxFieldChars']);
    expect(ErsteStatementImporter.maxReportedRows, limits['maxReportedRows']);
    expect(ErsteStatementImporter.ownTransferDescription, file['ownTransferDescription']);
    expect(ImportRule.ownAccountTransfer, file['hintOwnAccountTransfer']);
    expect(ImportRule.shape.pattern, '^${(file['ruleShape']! as String).replaceAll('(', '(?:')}\$');
  });

  test('Character.isDigit over every UTF-16 unit is the JDK\'s', () {
    final ranges = (file['isDigitUnits']! as List<Object?>).cast<List<Object?>>();
    bool java(int unit) => ranges.any((r) => unit >= (r[0]! as int) && unit <= (r[1]! as int));
    for (var unit = 0; unit <= 0xFFFF; unit++) {
      if (isJavaDigitUnit(unit) != java(unit)) {
        fail('U+${unit.toRadixString(16)}: Java says ${java(unit)}');
      }
    }
  });

  group('every case answers as the server answers', () {
    for (final entry in cases(file, 'cases')) {
      test('${entry['source']}: ${entry['name']}', () {
        final content = ErsteStatements.rebuild(entry['content']);
        final caseToday = CivilDate.parse(entry['today']! as String);
        final expected = entry['outcome']! as Map<String, Object?>;
        ParsedStatement? statement;
        ImportRejection? rejection;
        try {
          statement = parseErsteStatement(content, today: caseToday);
          if (entry['checkDestination'] == true) {
            final destination = entry['destination'] as String?;
            ErsteStatementImporter.checkDestination(
              statement.accountIdentity,
              destination == null || destination.isEmpty ? null : destination,
            );
          }
        } on ImportRejection catch (refused) {
          rejection = refused;
        }

        if (expected.containsKey('rule')) {
          expect(rejection, isNotNull, reason: 'the server refuses this statement');
          expect(rejection!.rule, expected['rule']);
          expect(rejection.rowNumbers, expected['rows']);
          expect(rejection.totalRows, expected['total']);
          proven.add(rejection.rule);
          return;
        }
        expect(rejection, isNull, reason: 'the server accepts this statement, not ${rejection?.rule}');
        expect(statement!.currency, expected['currency']);
        expect(statement.accountIdentity, expected['identity']);
        final rows = cases(expected, 'rows');
        expect(statement.rows, hasLength(rows.length));
        final fingerprints = <String>[];
        for (var i = 0; i < rows.length; i++) {
          final want = rows[i];
          final row = statement.rows[i];
          expect(row.rowNumber, want['row']);
          if (want.containsKey('rejection')) {
            expect(row.rejectionCode, want['rejection'], reason: 'row ${row.rowNumber}');
            expect(row.description, isNull);
            proven.add(row.rejectionCode!);
            continue;
          }
          expect(row.rejectionCode, isNull, reason: 'row ${row.rowNumber}');
          expect(row.transactionDate.toString(), want['date']);
          expect(row.bookingDate?.toString(), want['booking']);
          expect(row.amountMinor.toString(), want['amount']);
          expect(row.description, want['description']);
          expect(row.counterparty, want['counterparty']);
          expect(row.counterpartyAccount, want['counterpartyAccount']);
          expect(row.externalId, want['externalId']);
          expect(row.hintCode, want['hint']);
          if (row.hintCode != null) proven.add(row.hintCode!);
          final fingerprint = RowFingerprints.fingerprint(
            LocalIds.fromServerId(fingerprintAccount),
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
          expect(fingerprint, want['fingerprint'], reason: 'row ${row.rowNumber}');
          fingerprints.add(fingerprint);
        }
        final keys = RowFingerprints.keys(fingerprints);
        expect(
          [for (final key in keys) [key.fingerprint, key.occurrence]],
          expected['keys'],
        );
      });
    }
  });

  group('the destination check answers as the server answers', () {
    for (final entry in cases(file, 'destinations')) {
      final identity = entry['identity'] as String?;
      final stored = entry['stored'] as String?;
      test('${identity == null ? 'no identity' : identity.substring(0, 8)} into ${show(stored)}', () {
        Object? answer;
        try {
          ErsteStatementImporter.checkDestination(identity, stored);
        } on ImportRejection catch (refused) {
          answer = refused.rule;
        } on ArgumentError {
          answer = const {'error': 'IllegalArgumentException'};
        }
        if (entry.containsKey('error')) {
          expect(answer, {'error': entry['error']});
        } else {
          expect(answer, entry['rule']);
          if (answer is String) proven.add(answer);
        }
      });
    }
  });

  group('a format with a stable identifier is checked as on the server', () {
    for (final entry in cases(file, 'stableIdentifiers')) {
      final ids = (entry['externalIds']! as List<Object?>).cast<String?>();
      test(ids.map(show).join(', '), () {
        final statement = ParsedStatement('PLN', [
          for (var i = 0; i < ids.length; i++)
            ParsedRow.accepted(
              rowNumber: i + 1,
              transactionDate: CivilDate.parse('2026-03-01'),
              bookingDate: null,
              amountMinor: -100,
              description: 'TEST',
              counterparty: null,
              counterpartyAccount: null,
              externalId: ids[i],
            ),
        ], null);
        ImportRejection? refused;
        try {
          StatementBounds.validate(
            ErsteStatementImporter.formatId,
            statement,
            stableExternalId: true,
          );
        } on ImportRejection catch (rejection) {
          refused = rejection;
        }
        expect(refused?.rule, entry['rule']);
        expect(refused?.rowNumbers ?? const <int>[], entry['rows']);
        if (refused != null) proven.add(refused.rule);
      });
    }
  });

  test('parseErsteStatement never consults the clock: "today" decides the date range', () {
    // The same file is accepted a year before a date and refused a day after the year is over.
    final content = ErsteStatements.bytes([
      ErsteStatements.summary(),
      ErsteStatements.card('16-11-2027', '16-11-2027', 'SKLEP TESTOWY', '-1,00', 1),
    ]);
    expect(parseErsteStatement(content, today: today).rows, hasLength(1));
    expect(
      () => parseErsteStatement(content, today: CivilDate.parse('2026-11-15')),
      throwsA(isA<ImportRejection>().having((r) => r.rule, 'rule', ImportRule.dateOutOfRange)),
    );
  });

  // --- the rule catalogue (the server's ImportRuleCatalogueTest) ----------------------------------

  group('the rule catalogue', () {
    final emitted = (file['emittedRules']! as List<Object?>).cast<String>().toSet();

    test('names exactly the rules the server can emit, each in one stage', () {
      expect(ImportRule.parseStage.intersection(ImportRule.sessionStage), isEmpty);
      expect(
        emitted.difference(ImportRule.parseStage.union(ImportRule.sessionStage)),
        isEmpty,
        reason: 'the server emits these and Local has no code for them: add them to ImportRule',
      );
      expect(
        ImportRule.parseStage.union(ImportRule.sessionStage).difference(emitted),
        isEmpty,
        reason: 'Local names these and the server no longer emits them',
      );
      for (final rule in emitted) {
        expect(ImportRule.shape.hasMatch(rule), isTrue, reason: rule);
      }
    });

    test('every rule this package emits was named by a case that passed', () {
      // Runs after every case above (tests in a file run in order); a failed case adds nothing.
      expect(
        ImportRule.parseStage.difference(proven),
        isEmpty,
        reason: 'no passing case proves these rules',
      );
      expect(proven.difference(ImportRule.parseStage), isEmpty);
    });

    test('the session-stage rules are unit 8b\'s: the server proves them outside the parse', () {
      final elsewhere = (file['coveredElsewhere']! as Map<String, Object?>).keys.toSet();
      // The server covers each of them by a named test, not by the parse-stage catalogue; and
      // the catalogue's own cases that need a session are listed by the generator.
      expect(ImportRule.sessionStage.difference(elsewhere.union({ImportRule.accountNotFound})), isEmpty);
      final workflow = (file['workflowCases']! as List<Object?>).cast<String>();
      expect(workflow.where((c) => c.endsWith(ImportRule.accountNotFound)), isNotEmpty);
    });

    test('this package emits rules only through ImportRule, and never a session-stage one', () {
      final sources = Directory('lib/src/imports')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('import_rules.dart'));
      final literal = RegExp(r"""['"]([a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+)['"]""");
      for (final source in sources) {
        final text = source.readAsStringSync();
        for (final match in literal.allMatches(text)) {
          final value = match.group(1)!;
          if (value.startsWith('prudent.') || value.endsWith('.dart')) continue;
          if (emitted.contains(value) || RegExp(r'^[a-z_]+\.[a-z_]+$').hasMatch(value)) {
            fail('${source.path} spells the rule "$value" as a literal: use ImportRule');
          }
        }
        for (final name in [
          'accountNotFound',
          'alreadyImported',
          'commitCategoryUnavailable',
          'commitAccountUnavailable',
          'commitRowRefused',
        ]) {
          expect(text.contains('ImportRule.$name'), isFalse, reason: '${source.path} emits $name');
        }
      }
    });
  });
}
