package prudent.imports;

import java.nio.ByteBuffer;
import java.nio.charset.CharacterCodingException;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;

/**
 * The byte and delimiter layer of the Erste importer: strict UTF-8 decoding and an RFC 4180 reader
 * for the one shape the contract observed (docs/erste-csv-contract.md, "File-level format").
 *
 * <p>Everything here refuses rather than repairs, and nothing here puts statement text in an
 * exception: a failure is a rule code and, where there is one, a line.
 */
final class ErsteCsv {

  private ErsteCsv() {}

  /**
   * Decodes the file strictly as UTF-8 and checks its line structure.
   *
   * @return the lines, without their terminating LF, in order; never empty
   * @throws ImportRejectedException {@code encoding.bom}, {@code encoding.nul_byte}, {@code
   *     encoding.not_utf8}, {@code layout.line_ending} (any CR, so CRLF is refused) or {@code
   *     layout.no_final_newline}
   */
  static List<String> lines(byte[] content) {
    if (startsWith(content, 0xEF, 0xBB, 0xBF)
        || startsWith(content, 0xFE, 0xFF)
        || startsWith(content, 0xFF, 0xFE)) {
      // Refused, not stripped: a BOM says the file went through a tool the contract has not seen.
      throw new ImportRejectedException("encoding.bom");
    }
    for (byte b : content) {
      if (b == 0) {
        // UTF-16 and UTF-32 text without a BOM is full of NULs; so is a binary file.
        throw new ImportRejectedException("encoding.nul_byte");
      }
    }
    String text;
    try {
      text =
          StandardCharsets.UTF_8
              .newDecoder()
              .onMalformedInput(CodingErrorAction.REPORT)
              .onUnmappableCharacter(CodingErrorAction.REPORT)
              .decode(ByteBuffer.wrap(content))
              .toString();
    } catch (CharacterCodingException notUtf8) {
      // The exception's message names a byte offset; it is dropped on purpose.
      throw new ImportRejectedException("encoding.not_utf8");
    }
    if (text.indexOf('\r') >= 0) {
      throw new ImportRejectedException("layout.line_ending");
    }
    if (!text.endsWith("\n")) {
      throw new ImportRejectedException("layout.no_final_newline");
    }
    List<String> lines = new ArrayList<>();
    int start = 0;
    for (int end = text.indexOf('\n'); end >= 0; end = text.indexOf('\n', start)) {
      lines.add(text.substring(start, end));
      start = end + 1;
    }
    return lines;
  }

  /**
   * Splits one line into fields: comma-delimited, a field may be wrapped in double quotes (and then
   * may hold commas and {@code ""} for a quote), a quote anywhere else is an error.
   *
   * @return the fields, or {@code null} when the line is not well-formed CSV (an unterminated
   *     quote, a quote inside an unquoted field, text after a closing quote)
   */
  static List<String> fields(String line) {
    List<String> fields = new ArrayList<>();
    int i = 0;
    int n = line.length();
    while (true) {
      StringBuilder field = new StringBuilder();
      if (i < n && line.charAt(i) == '"') {
        i++;
        boolean closed = false;
        while (i < n) {
          char c = line.charAt(i++);
          if (c == '"') {
            if (i < n && line.charAt(i) == '"') {
              field.append('"');
              i++;
            } else {
              closed = true;
              break;
            }
          } else {
            field.append(c);
          }
        }
        if (!closed || (i < n && line.charAt(i) != ',')) {
          return null;
        }
      } else {
        while (i < n && line.charAt(i) != ',') {
          if (line.charAt(i) == '"') {
            return null;
          }
          field.append(line.charAt(i++));
        }
      }
      fields.add(field.toString());
      if (i >= n) {
        return fields;
      }
      i++; // the comma; a trailing comma yields a final empty field on the next pass
    }
  }

  private static boolean startsWith(byte[] content, int... prefix) {
    if (content.length < prefix.length) {
      return false;
    }
    for (int i = 0; i < prefix.length; i++) {
      if ((content[i] & 0xFF) != prefix[i]) {
        return false;
      }
    }
    return true;
  }
}
