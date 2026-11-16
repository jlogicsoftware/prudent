package prudent.parity;

import java.util.List;
import java.util.Map;

/**
 * The JSON writer of the golden vectors: no library, because the server has no JSON mapper on its
 * classpath on purpose (no Jackson, CLAUDE.md) and a test-only one would be a second JSON for one
 * file.
 *
 * <p>Every character outside printable ASCII is written as a {@code \\uXXXX} escape of its UTF-16
 * code units. That keeps the files ASCII (a diff shows {@code \\u00a0}, not an invisible space),
 * and it is the only way a lone surrogate — one of the hostile inputs — survives a file at all:
 * UTF-8 cannot encode one.
 *
 * <p>Objects and arrays at the top two levels are written one entry per line, deeper ones on one
 * line, so that a regenerated file diffs by case.
 */
final class GoldenJson {

  private GoldenJson() {}

  static String write(Object value) {
    StringBuilder out = new StringBuilder();
    write(out, value, 0);
    out.append('\n');
    return out.toString();
  }

  private static void write(StringBuilder out, Object value, int depth) {
    if (value == null) {
      out.append("null");
    } else if (value instanceof String text) {
      string(out, text);
    } else if (value instanceof Boolean || value instanceof Integer) {
      out.append(value);
    } else if (value instanceof Long number) {
      // int64 is a string, as in proto3 JSON: a JSON number is a double in most readers, and
      // 2^63 - 1 is not one.
      string(out, Long.toString(number));
    } else if (value instanceof Map<?, ?> map) {
      object(out, map, depth);
    } else if (value instanceof List<?> list) {
      array(out, list, depth);
    } else {
      throw new IllegalArgumentException("no JSON form for " + value.getClass());
    }
  }

  private static void object(StringBuilder out, Map<?, ?> map, int depth) {
    boolean pretty = depth < 2;
    out.append('{');
    boolean first = true;
    for (Map.Entry<?, ?> entry : map.entrySet()) {
      out.append(first ? "" : ",");
      first = false;
      newline(out, pretty, depth + 1);
      string(out, (String) entry.getKey());
      out.append(pretty ? ": " : ":");
      write(out, entry.getValue(), depth + 1);
    }
    if (!map.isEmpty()) {
      newline(out, pretty, depth);
    }
    out.append('}');
  }

  private static void array(StringBuilder out, List<?> list, int depth) {
    boolean pretty = depth < 2;
    out.append('[');
    for (int i = 0; i < list.size(); i++) {
      out.append(i == 0 ? "" : ",");
      newline(out, pretty, depth + 1);
      write(out, list.get(i), depth + 1);
    }
    if (!list.isEmpty()) {
      newline(out, pretty, depth);
    }
    out.append(']');
  }

  private static void newline(StringBuilder out, boolean pretty, int depth) {
    if (pretty) {
      out.append('\n').append("  ".repeat(depth));
    }
  }

  private static void string(StringBuilder out, String text) {
    out.append('"');
    for (int i = 0; i < text.length(); i++) {
      char c = text.charAt(i);
      if (c == '"' || c == '\\') {
        out.append('\\').append(c);
      } else if (c >= 0x20 && c < 0x7f) {
        out.append(c);
      } else {
        out.append(String.format("\\u%04x", (int) c));
      }
    }
    out.append('"');
  }
}
