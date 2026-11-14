package prudent.imports;

import jakarta.enterprise.context.ApplicationScoped;
import java.nio.charset.StandardCharsets;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;

/**
 * A format that exists only in the test classpath and claims a stable bank identifier, to prove the
 * switch in {@link StatementImporter#stableExternalId()} (M6, jlogicsoftware/prudent#75). Text: line
 * 1 is the currency; every other line is {@code date;amount-in-minor-units;description;entry-id}.
 */
@ApplicationScoped
public class TestStableIdImporter implements StatementImporter {

  public static final String FORMAT = "test-stable-id";

  @Override
  public String formatId() {
    return FORMAT;
  }

  @Override
  public boolean stableExternalId() {
    return true;
  }

  @Override
  public ParsedStatement parse(byte[] content, ImportContext context) {
    String[] lines = new String(content, StandardCharsets.UTF_8).split("\n", -1);
    List<ParsedRow> rows = new ArrayList<>();
    int number = 0;
    for (int i = 1; i < lines.length; i++) {
      if (lines[i].isEmpty()) {
        continue;
      }
      String[] fields = lines[i].split(";", -1);
      rows.add(
          ParsedRow.accepted(
              ++number,
              LocalDate.parse(fields[0]),
              null,
              Long.parseLong(fields[1]),
              fields[2],
              null,
              null,
              fields[3]));
    }
    return new ParsedStatement(lines[0], rows, null);
  }
}
