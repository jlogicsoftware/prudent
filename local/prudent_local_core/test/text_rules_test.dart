// Rules 3.7 and 3.8 (phase-0 §0.3) and finding F-04: Java's trim/strip/isBlank, the code-point count
// behind "500 characters", and Java's UTF-8, held to the JVM by test/golden/text.json.
import 'package:prudent_local_core/prudent_local_core.dart';
import 'package:test/test.dart';

import 'golden.dart';

void main() {
  final file = golden('text.json');

  Set<int> codePoints(String key) => {
    for (final range in (file[key]! as List<Object?>).cast<List<Object?>>())
      for (var cp = range[0]! as int; cp <= (range[1]! as int); cp++) cp,
  };

  test('isJavaWhitespace is Character.isWhitespace for every code point', () {
    final java = codePoints('javaWhitespace');
    for (var cp = 0; cp <= 0x10FFFF; cp++) {
      if (isJavaWhitespace(cp) != java.contains(cp)) {
        fail('U+${cp.toRadixString(16)}: Java ${java.contains(cp)}, Local ${isJavaWhitespace(cp)}');
      }
    }
  });

  test('isUnicodeWhiteSpace is the regex (?U)\\s for every code point', () {
    final java = codePoints('unicodeWhiteSpace');
    for (var cp = 0; cp <= 0x10FFFF; cp++) {
      if (isUnicodeWhiteSpace(cp) != java.contains(cp)) {
        fail(
          'U+${cp.toRadixString(16)}: Java ${java.contains(cp)}, Local ${isUnicodeWhiteSpace(cp)}',
        );
      }
    }
  });

  group('hostile inputs answer as the JVM answers', () {
    for (final entry in cases(file, 'cases')) {
      final input = entry['input'] as String?;
      if (input == null) continue;
      test(show(input), () {
        expect(javaTrim(input), entry['trim'], reason: 'trim()');
        expect(javaStrip(input), entry['strip'], reason: 'strip()');
        expect(javaIsBlank(input), entry['isBlank'], reason: 'isBlank()');
        expect(codePointCount(input), entry['codePoints'], reason: 'codePointCount');
        expect(_hex(javaUtf8(input)), entry['utf8'], reason: 'getBytes(UTF_8)');
        expect(
          attempt(() => TextRules.strippedNote(input)).containsKey('ok'),
          entry['stripNoteWithin500'],
          reason: 'the allocation and reset note rule',
        );
        expect(
          attempt(() => TextRules.trimmedOptionalNote(input)).containsKey('ok'),
          entry['trimNoteWithin500'],
          reason: 'the import row note rule',
        );
      });
    }
  });

  group('the composed rules keep the server\'s answers on the inputs that tell them apart', () {
    test('a note of 500 emoji is accepted although it is 1000 UTF-16 units (F-04)', () {
      final note = '\u{1F600}' * 500;
      expect(note.length, 1000);
      expect(TextRules.strippedNote(note), note);
      expect(() => TextRules.strippedNote('$note\u{1F600}'), throwsA(isA<Refusal>()));
    });

    test('combining marks count as code points, not as letters', () {
      expect(TextRules.strippedNote('é' * 250), hasLength(500));
      expect(() => TextRules.strippedNote('é' * 251), throwsA(isA<Refusal>()));
    });

    test(
      'a title of only a control character is not blank and trims to empty, as on the server',
      () {
        expect(TextRules.requiredTrimmed('\u0001', rule: '3.7'), '');
      },
    );

    test('a title of only an em space is blank and refused with 400', () {
      expect(
        () => TextRules.requiredTrimmed(' ', rule: '3.7'),
        throwsA(isA<Refusal>().having((r) => r.status, 'status', 400)),
      );
    });

    test('an optional text of a no-break space is kept, because trim() does not remove it', () {
      expect(TextRules.optionalTrimmed(' '), ' ');
      expect(TextRules.optionalTrimmed(' \t '), isNull);
    });
  });
}

String _hex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
