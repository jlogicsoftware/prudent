// Unit 8a (ADR-091): the row fingerprint, held to the server's RowFingerprints.java by
// test/golden/import_fingerprints.json — its normal form, both key schemes and occurrence numbers,
// and the two Unicode tables the normal form stands on: the JDK's root upper-casing (committed as
// lib/src/imports/java_root_upper_case.dart) and its canonical decompositions (unorm_dart's NFC).
import 'package:prudent_local_core/prudent_local_core.dart';
import 'package:test/test.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

import '../golden.dart';

void main() {
  final file = golden('import_fingerprints.json');

  test('the scheme prefixes and key shape are the server\'s', () {
    expect(RowFingerprints.fingerprintPrefix, file['fingerprintPrefix']);
    expect(RowFingerprints.stableIdPrefix, file['stableIdPrefix']);
    expect(RowFingerprints.keyShape.pattern, '^${file['keyShape']}\$');
  });

  test('root upper-casing is the JDK\'s table, every entry and nothing else', () {
    final java = {
      for (final entry in (file['rootUpperCase']! as List<Object?>).cast<List<Object?>>())
        entry[0]! as int: entry[1]! as String,
    };
    const regenerate = 'regenerate it: dart run tool/generate_root_upper_case.dart';
    expect(javaRootUpperCaseTable.length, java.length, reason: regenerate);
    for (final MapEntry(:key, :value) in java.entries) {
      expect(javaRootUpperCaseTable[key], value, reason: 'U+${key.toRadixString(16)}: $regenerate');
    }
    // And the function reads the table: ß is SS, the astral Adlam letter has its capital.
    expect(javaRootUpperCase('ß'), 'SS');
    expect(javaRootUpperCase(String.fromCharCode(0x1E922)), String.fromCharCode(0x1E900));
    expect(javaRootUpperCase(String.fromCharCodes([0x61, 0xD800, 0x62])), String.fromCharCodes([0x41, 0xD800, 0x42]));
  });

  group('NFC is the JDK\'s java.text.Normalizer', () {
    final table = (file['canonicalDecompositions']! as List<Object?>).cast<List<Object?>>();
    final decomposing = {for (final entry in table) entry[0]! as int};

    test('every code point with a canonical decomposition decomposes and composes as on the JDK', () {
      for (final entry in table) {
        final cp = entry[0]! as int;
        final char = String.fromCharCode(cp);
        final where = 'U+${cp.toRadixString(16)}';
        expect(unorm.nfd(char), entry[1], reason: '$where NFD');
        expect(RowFingerprints.nfc(char), entry[2], reason: '$where NFC');
        expect(RowFingerprints.nfc(entry[1]! as String), entry[2], reason: '$where NFC of its NFD');
      }
    });

    test('no other code point changes under NFC (the JDK\'s Unicode version, not a newer one)', () {
      expect(file['hangulSyllablesAlgorithmic'], isTrue);
      for (var cp = 0; cp <= 0x10FFFF; cp++) {
        if ((cp >= 0xD800 && cp <= 0xDFFF) || (cp >= 0xAC00 && cp <= 0xD7A3)) continue;
        if (decomposing.contains(cp)) continue;
        final char = String.fromCharCode(cp);
        if (RowFingerprints.nfc(char) != char) {
          fail('U+${cp.toRadixString(16)} changes locally and not on the server');
        }
      }
    });

    test('unorm_dart alone gets U+D7A4 wrong, which is why RowFingerprints.nfc exists', () {
      // If this starts failing, unorm_dart fixed its Hangul range: drop the workaround.
      const d7a4 = '\u{D7A4}';
      expect(unorm.nfc(d7a4), isNot(d7a4));
      expect(RowFingerprints.nfc(d7a4), d7a4);
      expect(RowFingerprints.nfc('$d7a4\u{11A8}'), '$d7a4\u{11A8}');
      expect(RowFingerprints.nfc('e\u{301}$d7a4\u{301}e\u{301}'), '\u{E9}$d7a4\u{301}\u{E9}');
    });

    test('every Hangul syllable decomposes algorithmically and composes back, as on the JDK', () {
      for (var cp = 0xAC00; cp <= 0xD7A3; cp++) {
        final index = cp - 0xAC00;
        final trailing = index % 28;
        final jamo = String.fromCharCodes([
          0x1100 + index ~/ (21 * 28),
          0x1161 + (index % (21 * 28)) ~/ 28,
          if (trailing != 0) 0x11A7 + trailing,
        ]);
        final char = String.fromCharCode(cp);
        expect(unorm.nfd(char), jamo, reason: 'U+${cp.toRadixString(16)}');
        expect(unorm.nfc(jamo), char, reason: 'U+${cp.toRadixString(16)}');
      }
    });
  });

  group('normalise answers as the server answers', () {
    for (final entry in cases(file, 'normalise')) {
      final input = entry['input'] as String?;
      test(show(input), () => expect(RowFingerprints.normalise(input), entry['normalise']));
    }
  });

  group('the v1 fingerprint is the server\'s', () {
    for (final entry in cases(file, 'fingerprints')) {
      final serverId = entry['accountId']! as String;
      test('${show(entry['description'])} / ${entry['amount']} / ${entry['date']}', () {
        final fields = FingerprintFields(
          transactionDate: CivilDate.parse(entry['date']! as String),
          amountMinor: int.parse(entry['amount']! as String),
          description: entry['description'] as String?,
          counterparty: entry['counterparty'] as String?,
          counterpartyAccount: entry['counterpartyAccount'] as String?,
        );
        final formatId = entry['formatId']! as String;
        final currency = entry['currency']! as String;
        // The server's id and the Local id of the same account give one fingerprint (ADR-103).
        expect(RowFingerprints.fingerprint(serverId, formatId, currency, fields), entry['fingerprint']);
        expect(
          RowFingerprints.fingerprint(LocalIds.fromServerId(serverId), formatId, currency, fields),
          entry['fingerprint'],
        );
      });
    }
  });

  group('the e1 stable-id key is the server\'s', () {
    for (final entry in cases(file, 'stableIdKeys')) {
      final externalId = entry['externalId'] as String?;
      test(show(externalId), () {
        Map<String, Object?> answer;
        try {
          final key = RowFingerprints.stableIdKey(
            entry['accountId']! as String,
            entry['formatId']! as String,
            externalId,
          );
          answer = {'ok': '${key.fingerprint}#${key.occurrence}'};
        } on ArgumentError {
          answer = {'error': 'IllegalArgumentException'};
        }
        expect(answer, entry['key']);
      });
    }
  });

  group('occurrence numbers are the server\'s', () {
    for (final entry in cases(file, 'keys')) {
      final fingerprints = (entry['fingerprints']! as List<Object?>).cast<String>();
      test('${fingerprints.length} fingerprints', () {
        expect(
          [for (final key in RowFingerprints.keys(fingerprints)) [key.fingerprint, key.occurrence]],
          entry['keys'],
        );
      });
    }
  });

  test('an account id that is neither form is refused, and never quoted', () {
    final fields = FingerprintFields(transactionDate: _date, amountMinor: -1);
    expect(
      () => RowFingerprints.fingerprint('ACCOUNT-QZX', 'erste-pl-csv', 'PLN', fields),
      throwsA(isA<ArgumentError>().having((e) => '$e', 'text', isNot(contains('QZX')))),
    );
  });

  test('a row key refuses a malformed fingerprint or occurrence', () {
    expect(() => RowKey('v1:abc', 1), throwsArgumentError);
    expect(() => RowKey('v1:${'a' * 64}', 0), throwsArgumentError);
    expect(RowKey('v1:${'a' * 64}', 2), RowKey('v1:${'a' * 64}', 2));
  });
}

final _date = CivilDate.parse('2026-03-10');
