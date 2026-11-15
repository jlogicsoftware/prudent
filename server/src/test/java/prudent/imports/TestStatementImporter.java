package prudent.imports;

import jakarta.enterprise.context.ApplicationScoped;
import java.nio.charset.StandardCharsets;
import java.time.LocalDate;
import java.time.format.DateTimeParseException;
import java.util.ArrayList;
import java.util.List;
import prudent.account.AccountEntity;

/**
 * A trivial importer that exists only in the test classpath, to exercise the workflow without the
 * Erste parser (jlogicsoftware/prudent#73). Its "statement" is UTF-8 text: line 1 is the currency,
 * optionally followed by {@code ;account-name} (the statement's own "account number"), and every
 * other line is {@code date;amount-in-minor-units;description;ignored}.
 *
 * <p>It implements {@link #checkDestination} the way the Erste importer will: the statement's
 * identity token must equal the identity of the destination's name (the stand-in for an account
 * number, which {@link AccountEntity} does not have yet). A statement with no account name carries
 * no identity and fits any account.
 *
 * <p>The fourth field is read and thrown away on purpose: the tests plant a marker there and then
 * look for it in the database, so a regression that persisted the raw file would be found.
 */
@ApplicationScoped
public class TestStatementImporter implements StatementImporter {

  public static final String FORMAT = "test-format";

  @Override
  public String formatId() {
    return FORMAT;
  }

  @Override
  public ParsedStatement parse(byte[] content, ImportContext context) {
    String[] lines = new String(content, StandardCharsets.UTF_8).split("\n", -1);
    if (lines[0].equals("FORBIDDEN")) {
      throw new ImportRejectedException("layout.unsupported");
    }
    List<ParsedRow> rows = new ArrayList<>();
    for (int i = 1; i < lines.length; i++) {
      if (lines[i].isEmpty()) {
        continue;
      }
      int number = i;
      String[] fields = lines[i].split(";", -1);
      if (fields.length != 4) {
        throw new ImportRejectedException("row.field_count", number);
      }
      LocalDate date;
      try {
        date = LocalDate.parse(fields[0]);
      } catch (DateTimeParseException bad) {
        throw new ImportRejectedException("date.invalid", number);
      }
      long amount;
      try {
        amount = Long.parseLong(fields[1]);
      } catch (NumberFormatException bad) {
        rows.add(ParsedRow.rejected(number, "amount.invalid"));
        continue;
      }
      if (amount == 0) {
        rows.add(ParsedRow.rejected(number, "amount.zero"));
        continue;
      }
      rows.add(ParsedRow.accepted(number, date, null, amount, fields[2], null, null, null));
    }
    String[] head = lines[0].split(";", -1);
    String identity = head.length > 1 ? ParsedStatement.identityOf(head[1]) : null;
    return new ParsedStatement(head[0], rows, identity);
  }

  @Override
  public void checkDestination(String statementIdentity, AccountEntity destination) {
    if (statementIdentity != null
        && !statementIdentity.equals(ParsedStatement.identityOf(destination.name))) {
      throw new ImportRejectedException("account.identity_mismatch");
    }
  }
}
