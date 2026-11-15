// How an import refusal becomes a sentence (jlogicsoftware/prudent#74): the rule code and rows are
// read from the server's one fixed message shape, every code the server can emit has a sentence in
// every shipped language, and nothing else in a message can reach the screen.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prudent/imports/import_failure.dart';
import 'package:prudent/imports/import_failure_text.dart';
import 'package:prudent/imports/import_rule_messages.dart';
import 'package:prudent/l10n/generated/prudent_localizations.dart';
import 'package:zen_core/zen_core.dart';
import 'package:zen_transport/zen_transport.dart' as transport;

ZenError _server(String code, String message) =>
    transport.ZenTransportError(transport.ZenError(code: code, message: message));

void main() {
  group('ImportFailure.from', () {
    test('reads the rule and the rows from the server message', () {
      final one = ImportFailure.from(
        _server('invalid', 'The statement was rejected at row 7 (amount.zero).'),
      );
      expect(one.kind, ImportFailureKind.rule);
      expect(one.ruleCode, 'amount.zero');
      expect(one.rowNumbers, [7]);
      expect(one.moreRows, 0);

      final many = ImportFailure.from(
        _server('invalid', 'The statement was rejected at rows 3, 5, 9 and 12 more (date.invalid).'),
      );
      expect(many.rowNumbers, [3, 5, 9]);
      expect(many.moreRows, 12);

      final whole = ImportFailure.from(
        _server('invalid', 'The statement was rejected (encoding.not_utf8).'),
      );
      expect(whole.ruleCode, 'encoding.not_utf8');
      expect(whole.rowNumbers, isEmpty);
    });

    test('a rule at commit arrives as a 409 and is still a rule', () {
      final failure = ImportFailure.from(
        _server('conflict', 'The statement was rejected (account.identity_mismatch).'),
      );
      expect(failure.kind, ImportFailureKind.rule);
      expect(failure.ruleCode, 'account.identity_mismatch');
    });

    test('a message that only resembles the shape is not trusted', () {
      for (final message in [
        'The statement was rejected (amount.zero). TEST SECRET DESCRIPTION',
        'TEST SECRET. The statement was rejected (amount.zero).',
        'The statement was rejected at row 7 (Amount Zero).',
        'The statement was rejected at row x (amount.zero).',
      ]) {
        final failure = ImportFailure.from(_server('invalid', message));
        expect(failure.kind, ImportFailureKind.invalid, reason: message);
        expect(failure.ruleCode, isNull);
      }
    });

    test('the wire code decides the kind when there is no rule', () {
      ImportFailureKind kind(String code, {bool creating = false}) =>
          ImportFailure.from(_server(code, 'x'), creating: creating).kind;

      expect(kind('invalid'), ImportFailureKind.invalid);
      expect(kind('conflict'), ImportFailureKind.conflict);
      expect(kind('conflict', creating: true), ImportFailureKind.tooManyOpen);
      expect(kind('not_found'), ImportFailureKind.notFound);
      expect(kind('unavailable'), ImportFailureKind.unavailable);
      expect(kind('network_error'), ImportFailureKind.network);
      expect(kind('decode_error'), ImportFailureKind.unexpected);
      expect(ImportFailure.from(const ZenUnknownError('boom')).kind, ImportFailureKind.unexpected);
    });

    test('only a conflict or a missing session asks for a reload', () {
      expect(ImportFailure.from(_server('conflict', 'x')).shouldReload, isTrue);
      expect(ImportFailure.from(_server('not_found', 'x')).shouldReload, isTrue);
      expect(ImportFailure.from(_server('invalid', 'x')).shouldReload, isFalse);
      expect(ImportFailure.from(_server('network_error', 'x')).shouldReload, isFalse);
    });

    test('keeps no part of the server message', () {
      final failure = ImportFailure.from(_server('invalid', 'TEST SECRET DESCRIPTION'));
      expect(failure.ruleCode, isNull);
      expect(failure.rowNumbers, isEmpty);
    });
  });

  group('sentences', () {
    for (final locale in PrudentLocalizations.supportedLocales) {
      test('every known rule code has a sentence in ${locale.languageCode}', () {
        final t = lookupPrudentLocalizations(locale);
        for (final code in importRuleCodes) {
          final text = importRuleMessage(t, code);
          expect(text, isNotNull, reason: code);
          expect(text!.trim(), isNotEmpty, reason: code);
          // A sentence says what to do; none is just the code or the server's English.
          expect(text.contains(code), isFalse, reason: code);
        }
      });

      test('an unknown rule falls back to a sentence that names the code (${locale.languageCode})', () {
        final t = lookupPrudentLocalizations(locale);
        expect(importRuleMessage(t, 'future.new_rule'), isNull);
        final text = importFailureMessage(
          t,
          const ImportFailure(kind: ImportFailureKind.rule, ruleCode: 'future.new_rule'),
        );
        expect(text, contains('future.new_rule'));
      });
    }

    for (final locale in PrudentLocalizations.supportedLocales) {
      test('no sentence is a placeholder, the server English, or another rule\'s sentence (${locale.languageCode})', () {
        final t = lookupPrudentLocalizations(locale);
        final seen = <String, String>{};
        for (final code in importRuleCodes) {
          final text = importRuleMessage(t, code)!;
          expect(text.contains('{') || text.contains('}'), isFalse, reason: code);
          expect(text.contains('The statement was rejected'), isFalse, reason: code);
          final other = seen[text];
          expect(other, isNull, reason: '$code repeats the sentence of $other');
          seen[text] = code;
        }
      });
    }

    test('rows read as a list, with how many more', () {
      final t = lookupPrudentLocalizations(const Locale('en'));
      expect(
        importFailureRows(t, const ImportFailure(kind: ImportFailureKind.rule, rowNumbers: [3, 5], moreRows: 2)),
        'Rows involved: 3, 5 and 2 more',
      );
      expect(
        importFailureRows(t, const ImportFailure(kind: ImportFailureKind.rule, rowNumbers: [3])),
        'Rows involved: 3',
      );
      expect(importFailureRows(t, const ImportFailure(kind: ImportFailureKind.invalid)), isNull);
    });

    test('every failure kind has a sentence', () {
      final t = lookupPrudentLocalizations(const Locale('en'));
      for (final kind in ImportFailureKind.values) {
        final text = importFailureMessage(
          t,
          ImportFailure(kind: kind, ruleCode: kind == ImportFailureKind.rule ? 'amount.zero' : null),
        );
        expect(text, isNotEmpty, reason: '$kind');
      }
    });
  });

  test('the client knows every rule code the server can emit', () {
    // The codes are the server's: an importer rule, a duplicate stage code and a row hint. A code
    // added there without a sentence here would reach a user as "code x.y", so this fails first.
    final dir = Directory('../server/src/main/java/prudent/imports');
    expect(dir.existsSync(), isTrue, reason: 'run from the client directory of the repository');
    final emitted = serverRuleCodes(dir);
    expect(emitted, isNotEmpty);
    expect(emitted.difference(importRuleCodes.toSet()), isEmpty);
    // And the reverse: no sentence for a code nothing can emit.
    expect(importRuleCodes.toSet().difference(emitted), isEmpty);
  });

  test('the list of rule codes has no repeats', () {
    expect(importRuleCodes.toSet().length, importRuleCodes.length);
  });

  test('the scan follows every way a code is produced, in any file of the package', () {
    // The server builds a code as an exception's argument, a failure's, a row's, a returned name or
    // a constant, in several files, so the scan reads every literal of the shape in every file
    // rather than a list of call patterns or file names. This holds that scan to what it must see.
    final dir = Directory.systemTemp.createTempSync('rule_scan');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/A.java').writeAsStringSync('''
      // "commented.out" is not a code, nor is the one in /* "block.comment" */ this line
      class A {
        void f() { throw new ImportRejectedException("a.thrown"); }
        Object g() { return ParsedRow.rejected(3, "b.rejected"); }
        String h() { return "c.returned_code"; }
        static final String K = "d.constant9";
        String hint = x.setHint("jakarta.persistence.lock.timeout", -2);
        String key = "prudent.import.row." + P;
      }
    ''');
    expect(serverRuleCodes(dir), {'a.thrown', 'b.rejected', 'c.returned_code', 'd.constant9'});
  });
}

/// Every string literal in the package's Java sources that has the shape of a rule code (dotted,
/// lower case), minus the literals that are configuration keys of another library. Comments are
/// dropped first, so prose that quotes a code is not a code.
Set<String> serverRuleCodes(Directory dir) {
  final code = RegExp(r'^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+$');
  final literal = RegExp(r'"([^"\\\n]*)"');
  const notCodes = ['jakarta.', 'java.', 'javax.', 'org.', 'com.', 'prudent.'];
  final emitted = <String>{};
  final files = dir.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.java'));
  expect(files, isNotEmpty);
  for (final file in files) {
    final source = file
        .readAsStringSync()
        .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
        .replaceAll(RegExp(r'//[^\n]*'), '');
    for (final m in literal.allMatches(source)) {
      final text = m.group(1)!;
      if (code.hasMatch(text) && !notCodes.any(text.startsWith)) emitted.add(text);
    }
  }
  return emitted;
}
