import 'dart:convert';
import 'dart:typed_data';

import 'import_rules.dart';

/// The byte and delimiter layer of the Erste importer — the server's `ErsteCsv.java`: strict UTF-8
/// and an RFC 4180 reader for the one shape `docs/erste-csv-contract.md` observed.
///
/// Everything here refuses rather than repairs, and no refusal carries statement text.
abstract final class ErsteCsv {
  /// Decodes [content] strictly as UTF-8 and checks its line structure: the lines without their
  /// LF, in order, never empty. Refuses with `encoding.bom`, `encoding.nul_byte`,
  /// `encoding.not_utf8`, `layout.line_ending` (any CR) or `layout.no_final_newline`.
  static List<String> lines(Uint8List content) {
    if (_startsWith(content, const [0xEF, 0xBB, 0xBF]) ||
        _startsWith(content, const [0xFE, 0xFF]) ||
        _startsWith(content, const [0xFF, 0xFE])) {
      throw ImportRejection(ImportRule.encodingBom);
    }
    if (content.contains(0)) throw ImportRejection(ImportRule.encodingNulByte);
    if (!isWellFormedUtf8(content)) throw ImportRejection(ImportRule.encodingNotUtf8);
    final text = utf8.decode(content);
    if (text.contains('\r')) throw ImportRejection(ImportRule.lineEnding);
    if (!text.endsWith('\n')) throw ImportRejection(ImportRule.noFinalNewline);
    final lines = text.split('\n');
    return lines.sublist(0, lines.length - 1);
  }

  /// Whether [bytes] is well-formed UTF-8 as Java's decoder with `CodingErrorAction.REPORT` reads
  /// it — the Unicode standard's table 3-7: no overlong form, no encoded surrogate, nothing above
  /// U+10FFFF, no stray or missing continuation byte.
  ///
  /// Checked here rather than left to `utf8.decode`, so that what is refused does not depend on how
  /// lenient one SDK's decoder is; the decode that follows cannot fail.
  static bool isWellFormedUtf8(List<int> bytes) {
    var i = 0;
    final n = bytes.length;
    bool continuation(int at, [int low = 0x80, int high = 0xBF]) =>
        at < n && bytes[at] >= low && bytes[at] <= high;
    while (i < n) {
      final b = bytes[i];
      if (b < 0x80) {
        i += 1;
      } else if (b >= 0xC2 && b <= 0xDF) {
        if (!continuation(i + 1)) return false;
        i += 2;
      } else if (b >= 0xE0 && b <= 0xEF) {
        final low = b == 0xE0 ? 0xA0 : 0x80;
        final high = b == 0xED ? 0x9F : 0xBF;
        if (!continuation(i + 1, low, high) || !continuation(i + 2)) return false;
        i += 3;
      } else if (b >= 0xF0 && b <= 0xF4) {
        final low = b == 0xF0 ? 0x90 : 0x80;
        final high = b == 0xF4 ? 0x8F : 0xBF;
        if (!continuation(i + 1, low, high) || !continuation(i + 2) || !continuation(i + 3)) {
          return false;
        }
        i += 4;
      } else {
        return false;
      }
    }
    return true;
  }

  /// Splits one line into fields: comma-delimited; a field may be wrapped in double quotes, and
  /// may then hold commas and `""` for a quote; a quote anywhere else is an error. `null` when the
  /// line is not well-formed (an unterminated quote, a quote inside an unquoted field, text after a
  /// closing quote). Reads UTF-16 units, as Java's `charAt` does.
  static List<String>? fields(String line) {
    final fields = <String>[];
    var i = 0;
    final n = line.length;
    const quote = 0x22;
    const comma = 0x2C;
    while (true) {
      final field = StringBuffer();
      if (i < n && line.codeUnitAt(i) == quote) {
        i++;
        var closed = false;
        while (i < n) {
          final c = line.codeUnitAt(i++);
          if (c == quote) {
            if (i < n && line.codeUnitAt(i) == quote) {
              field.writeCharCode(quote);
              i++;
            } else {
              closed = true;
              break;
            }
          } else {
            field.writeCharCode(c);
          }
        }
        if (!closed || (i < n && line.codeUnitAt(i) != comma)) return null;
      } else {
        while (i < n && line.codeUnitAt(i) != comma) {
          if (line.codeUnitAt(i) == quote) return null;
          field.writeCharCode(line.codeUnitAt(i++));
        }
      }
      fields.add(field.toString());
      if (i >= n) return fields;
      i++; // the comma; a trailing comma yields a final empty field on the next pass
    }
  }

  static bool _startsWith(Uint8List content, List<int> prefix) {
    if (content.length < prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (content[i] != prefix[i]) return false;
    }
    return true;
  }
}
