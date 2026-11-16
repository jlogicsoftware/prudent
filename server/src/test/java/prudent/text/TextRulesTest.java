package prudent.text;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;

import com.google.protobuf.Struct;
import com.google.protobuf.Value;
import com.google.protobuf.util.JsonFormat;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Random;
import java.util.UUID;
import org.junit.jupiter.api.Test;

/**
 * Runs the expected-behaviour vectors in {@code src/test/resources/text-rules/} (ADR-106). The same
 * files are what Prudent Local's parity suite reads, so a disagreement between the two sides is a
 * failing vector rather than a matter of opinion. Plain JUnit: the rules touch no database.
 */
class TextRulesTest {

  private static Struct load(String name) throws IOException {
    try (InputStream in = TextRulesTest.class.getResourceAsStream("/text-rules/" + name)) {
      Struct.Builder builder = Struct.newBuilder();
      JsonFormat.parser().merge(new InputStreamReader(in, StandardCharsets.UTF_8), builder);
      return builder.build();
    }
  }

  private static List<Value> cases(String file, String key) throws IOException {
    return load(file).getFieldsOrThrow(key).getListValue().getValuesList();
  }

  @Test
  void searchTerm_matchesTheVectors() throws IOException {
    for (Value c : cases("search-vectors.json", "term")) {
      Struct s = c.getStructValue();
      String id = s.getFieldsOrThrow("id").getStringValue();
      Value search = s.getFieldsOrThrow("search");
      Value term = s.getFieldsOrThrow("term");
      String raw = search.hasNullValue() ? null : search.getStringValue();
      if (term.hasNullValue()) {
        assertNull(TextRules.searchTerm(raw), id);
      } else {
        assertEquals(term.getStringValue(), TextRules.searchTerm(raw), id);
      }
    }
  }

  @Test
  void matchesAny_matchesTheVectors() throws IOException {
    for (Value c : cases("search-vectors.json", "match")) {
      Struct s = c.getStructValue();
      String id = s.getFieldsOrThrow("id").getStringValue();
      String term = s.getFieldsOrThrow("term").getStringValue();
      List<Value> fields = s.getFieldsOrThrow("fields").getListValue().getValuesList();
      List<Value> expected = s.getFieldsOrThrow("matches").getListValue().getValuesList();
      for (int i = 0; i < fields.size(); i++) {
        Value f = fields.get(i);
        String field = f.hasNullValue() ? null : f.getStringValue();
        assertEquals(
            expected.get(i).getBoolValue(), TextRules.matchesAny(term, field), id + "[" + i + "]");
      }
    }
  }

  @Test
  void compareNames_matchesTheVectors() throws IOException {
    for (Value c : cases("name-order-vectors.json", "orders")) {
      Struct s = c.getStructValue();
      String id = s.getFieldsOrThrow("id").getStringValue();
      List<String[]> rows = new ArrayList<>();
      for (Value pair : s.getFieldsOrThrow("input").getListValue().getValuesList()) {
        List<Value> p = pair.getListValue().getValuesList();
        rows.add(new String[] {p.get(0).getStringValue(), p.get(1).getStringValue()});
      }
      // Every permutation of a vector's input must sort identically: the rule is a total order.
      for (int shuffle = 0; shuffle < 20; shuffle++) {
        Collections.shuffle(rows, new Random(shuffle));
        List<String[]> sorted = new ArrayList<>(rows);
        sorted.sort(
            (a, b) ->
                TextRules.compareNames(a[0], UUID.fromString(a[1]), b[0], UUID.fromString(b[1])));
        if (s.containsFields("sorted")) {
          assertEquals(strings(s, "sorted"), sorted.stream().map(r -> r[0]).toList(), id);
        } else {
          assertEquals(strings(s, "sortedIds"), sorted.stream().map(r -> r[1]).toList(), id);
        }
      }
    }
  }

  private static List<String> strings(Struct s, String key) {
    return s.getFieldsOrThrow(key).getListValue().getValuesList().stream()
        .map(Value::getStringValue)
        .toList();
  }
}
