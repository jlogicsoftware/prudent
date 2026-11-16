// Rule 3.2 (phase-0 §0.3): the ISO-4217 list and the normalisation of a currency code, held to the
// server's Currencies.java by test/golden/currencies.json.
import 'package:prudent_local_core/prudent_local_core.dart';
import 'package:test/test.dart';

import 'golden.dart';

void main() {
  final file = golden('currencies.json');

  test('the ISO-4217 set is exactly the JDK table the server validates against', () {
    final java = (file['iso4217']! as List<Object?>).cast<String>().toSet();
    expect(
      iso4217Codes.difference(java),
      isEmpty,
      reason: 'codes Local accepts and the server refuses',
    );
    expect(
      java.difference(iso4217Codes),
      isEmpty,
      reason: 'codes the server accepts and Local refuses: update lib/src/iso4217.dart',
    );
  });

  test('every code point that root upper-cases to ASCII capitals is folded as Java folds it', () {
    // Each entry is a code point other than a-z/A-Z whose Java toUpperCase(ROOT) is only A-Z. The
    // port must fold exactly these; checking normalize() on each, alone and inside a code, proves it.
    final table = cases(file, 'rootUpperCaseToAsciiCapitals');
    expect(table, isNotEmpty);
    for (final entry in table) {
      final char = String.fromCharCode(entry['codePoint']! as int);
      expect(
        Currencies.normalize(char),
        entry['upper'],
        reason: 'U+${(entry['codePoint']! as int).toRadixString(16)}',
      );
    }
    // And no other character folds to ASCII: every non-ASCII BMP and astral code point outside the
    // table normalises to itself (Local never invents a valid code Java would not).
    final folding = {for (final entry in table) entry['codePoint']! as int};
    for (var cp = 0x80; cp <= 0x10FFFF; cp++) {
      if (folding.contains(cp) || (cp >= 0xD800 && cp <= 0xDFFF)) continue;
      final char = String.fromCharCode(cp);
      final normalized = Currencies.normalize(char)!;
      if (RegExp(r'^[A-Z]+$').hasMatch(normalized)) {
        fail('U+${cp.toRadixString(16)} folds to ASCII capitals locally but not on the server');
      }
    }
  });

  group('hostile inputs answer as the server answers', () {
    for (final entry in cases(file, 'cases')) {
      final input = entry['input'] as String?;
      test(show(input), () {
        expect(Currencies.isValid(input), entry['isValid'], reason: 'isValid');
        expect(attempt(() => Currencies.parse(input)), entry['parse'], reason: 'parse');
        // normalize() is exact wherever the server stores its result: for a valid code.
        if (entry['isValid'] == true) {
          expect(Currencies.normalize(input), entry['normalize'], reason: 'normalize');
        }
      });
    }
  });
}
