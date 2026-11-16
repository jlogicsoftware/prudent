package prudent.imports;

import java.io.IOException;
import java.time.Clock;
import java.time.LocalDate;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import prudent.account.AccountEntity;
import prudent.imports.ImportFailureCatalogue.Destination;
import prudent.imports.ImportTestSupport.Erste;

/**
 * Opens the package-private import code to the golden-vector generator ({@link
 * prudent.parity.GoldenVectorsTest}), so that Prudent Local's port of the Erste importer and the
 * row fingerprints (unit 8a of {@code docs/plans/PRUDENT-LOCAL-PLAN.md}) is held to the methods the
 * server runs and to the failure catalogue of ADR-094, not to a copy of either.
 *
 * <p><strong>The parse stage.</strong> {@link #parseStage} is what {@link ImportWorkflow#create}
 * does to an upload before a session exists: the empty and size bounds, the importer, {@link
 * ParsedStatements#validate} and, when a destination is named, {@link
 * StatementImporter#checkDestination}. Everything after that — sessions, the destination's owner,
 * state and currency, duplicates against the ledger and the commit — is unit 8b's and is not here.
 */
public final class ImportRulesAccess {

  private ImportRulesAccess() {}

  /** "Today" for every catalogue case, so that a regenerated file does not move with the clock. */
  public static final LocalDate TODAY = LocalDate.of(2026, 11, 16);

  /** The statement's own account (the destination that matches) and another of the user's. */
  public static final String ACCOUNT = Erste.ACCOUNT;

  public static final String OTHER_ACCOUNT = Erste.OTHER_ACCOUNT;

  /** A catalogue case the parse stage decides, with what the catalogue says it must answer. */
  public record Case(
      String name,
      byte[] content,
      /** {@code null}: no destination; {@code ""}: an account without a number; else its number. */
      String destinationNumber,
      boolean checkDestination,
      String expectedRule,
      List<Integer> expectedRows,
      int expectedTotal,
      List<String> expectedCodes) {}

  /** The answer of the parse stage: a statement, or the rule that refused it. */
  public record Outcome(ParsedStatement statement, ImportRejectedException rejection) {}

  /**
   * The catalogue cases the parse stage decides: every flagged case, and every refusal whose
   * destination is none, the statement's own account, another numbered account or an account
   * without a number. The rest ({@link #workflowCases}) are decided by the session workflow.
   */
  public static List<Case> catalogue() {
    List<Case> out = new ArrayList<>();
    for (ImportFailureCatalogue.Refusal refusal : ImportFailureCatalogue.refusals()) {
      if (!isParseStage(refusal.destination())) {
        continue;
      }
      out.add(
          new Case(
              refusal.name(),
              refusal.content(),
              destinationNumber(refusal.destination()),
              refusal.destination() != Destination.NONE,
              refusal.rule(),
              refusal.rows(),
              refusal.total(),
              null));
    }
    for (ImportFailureCatalogue.Flagged flagged : ImportFailureCatalogue.flagged()) {
      out.add(new Case(flagged.name(), flagged.content(), ACCOUNT, true, null, null, 0, flagged.codes()));
    }
    return out;
  }

  /** The names of the refusals the session workflow decides (unit 8b), with what they expect. */
  public static List<String> workflowCases() {
    List<String> out = new ArrayList<>();
    for (ImportFailureCatalogue.Refusal refusal : ImportFailureCatalogue.refusals()) {
      if (!isParseStage(refusal.destination())) {
        out.add(refusal.name() + " -> " + (refusal.rule() == null ? "message" : refusal.rule()));
      }
    }
    return out;
  }

  private static boolean isParseStage(Destination destination) {
    return switch (destination) {
      case ERSTE, NONE, OTHER_NUMBER, UNNUMBERED -> true;
      default -> false;
    };
  }

  private static String destinationNumber(Destination destination) {
    return switch (destination) {
      case ERSTE -> ACCOUNT;
      case OTHER_NUMBER -> OTHER_ACCOUNT;
      case UNNUMBERED -> "";
      default -> null;
    };
  }

  /**
   * Runs one upload through the parse stage as {@link ImportWorkflow#create} does.
   *
   * @param destinationNumber the destination's stored number ({@code ""} or {@code null} for none),
   *     read only when {@code checkDestination}
   */
  public static Outcome parseStage(
      byte[] content, LocalDate today, boolean checkDestination, String destinationNumber) {
    try {
      if (content == null || content.length == 0) {
        throw new ImportRejectedException("statement.empty_upload");
      }
      if (content.length > ImportWorkflow.MAX_CONTENT_BYTES) {
        throw new ImportRejectedException("statement.too_large");
      }
      ErsteStatementImporter importer = new ErsteStatementImporter();
      importer.clock = Clock.fixed(today.atStartOfDay(ZoneOffset.UTC).toInstant(), ZoneOffset.UTC);
      ParsedStatement parsed = importer.parse(content, new ImportContext(UUID.randomUUID(), null));
      ParsedStatements.validate(
          importer.formatId(), parsed, ParsedStatements.DEFAULT_MAX_ROWS, importer.stableExternalId());
      if (checkDestination) {
        AccountEntity destination = new AccountEntity();
        destination.accountNumber =
            destinationNumber == null || destinationNumber.isEmpty() ? null : destinationNumber;
        importer.checkDestination(parsed.accountIdentity(), destination);
      }
      return new Outcome(parsed, null);
    } catch (ImportRejectedException rejected) {
      return new Outcome(null, rejected);
    }
  }

  /** {@link ParsedStatements#validate} with a stable-identifier format, for the identifier rules. */
  public static ImportRejectedException validateStable(ParsedStatement statement) {
    try {
      ParsedStatements.validate("erste-pl-csv", statement, ParsedStatements.DEFAULT_MAX_ROWS, true);
      return null;
    } catch (ImportRejectedException rejected) {
      return rejected;
    }
  }

  /** {@link ErsteStatementImporter#checkDestination} with a statement identity of the caller's. */
  public static ImportRejectedException checkDestination(String identity, String storedNumber) {
    AccountEntity destination = new AccountEntity();
    destination.accountNumber = storedNumber;
    try {
      new ErsteStatementImporter().checkDestination(identity, destination);
      return null;
    } catch (ImportRejectedException rejected) {
      return rejected;
    }
  }

  /** The base statement of the catalogue with one field set (see {@link Erste#withField}). */
  public static byte[] withField(int row, int field, String value) {
    return Erste.withField(row, field, value);
  }

  /** The base statement of the catalogue with both dates of transaction row {@code row} set. */
  public static byte[] withDates(int row, String booking, String transaction) {
    List<String[]> rows = Erste.base();
    rows.get(row)[0] = booking;
    rows.get(row)[1] = transaction;
    return Erste.bytes(Erste.lines(rows));
  }

  /** One field of the base statement: row 0 is the summary, row n transaction row n. */
  public static String baseField(int row, int field) {
    return Erste.base().get(row)[field];
  }

  /** {@link Erste#manyCards}, for a case too large to write into a golden file. */
  public static byte[] manyCards(int count) {
    return Erste.manyCards(count);
  }

  /** Every rule code the import package's sources can emit ({@link ImportRuleCatalogueTest}). */
  public static Set<String> emittedRules() throws IOException {
    return ImportRuleCatalogueTest.emittedRules();
  }

  /** The rules the catalogue's cases do not reach, with the server test that proves each. */
  public static Map<String, String> coveredElsewhere() {
    return ImportFailureCatalogue.coveredElsewhere();
  }

  public static int maxContentBytes() {
    return ImportWorkflow.MAX_CONTENT_BYTES;
  }

  public static int maxRows() {
    return ParsedStatements.DEFAULT_MAX_ROWS;
  }

  public static int maxFieldChars() {
    return ParsedStatements.MAX_FIELD_CHARS;
  }

  public static int maxReportedRows() {
    return ErsteStatementImporter.MAX_REPORTED_ROWS;
  }
}
