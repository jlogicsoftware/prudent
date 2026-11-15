package prudent.imports;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static prudent.imports.ImportTestSupport.commit;
import static prudent.imports.ImportTestSupport.defaults;
import static prudent.imports.ImportTestSupport.error;
import static prudent.imports.ImportTestSupport.preview;
import static prudent.imports.ImportTestSupport.session;
import static prudent.imports.ImportTestSupport.uploadErste;

import io.quarkus.narayana.jta.QuarkusTransaction;
import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.security.TestSecurity;
import io.restassured.response.Response;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import java.util.logging.Handler;
import java.util.logging.LogRecord;
import java.util.logging.Logger;
import java.util.stream.Stream;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.Arguments;
import org.junit.jupiter.params.provider.MethodSource;
import prudent.PrudentTest;
import prudent.account.AccountBalance;
import prudent.account.AccountEntity;
import prudent.imports.ImportFailureCatalogue.Destination;
import prudent.imports.ImportFailureCatalogue.Flagged;
import prudent.imports.ImportFailureCatalogue.Refusal;
import prudent.proto.v1.ImportRow;
import prudent.proto.v1.ImportRowStatus;
import prudent.proto.v1.ImportSession;
import prudent.proto.v1.ImportSessionState;
import prudent.record.RecordEntity;
import zen.proto.v1.ZenError;

/**
 * The failure and drift matrix (M6, jlogicsoftware/prudent#77, ADR-094): every statement of {@link
 * ImportFailureCatalogue} — malformed, structurally changed, mixed-currency, oversized, misdirected —
 * goes through the real HTTP API and the real Erste importer, and each case proves both halves of
 * the epic's claim at once. The refusal is <em>actionable</em> (the status, the rule code and the
 * bounded row numbers, and no statement text, account number or amount in the body or in a log
 * line), and it is <em>safe</em>: the database is exactly as it was, for the caller and for another
 * user, down to every record, session, row and account, and the next good upload still works.
 *
 * <p>A statement the importer accepts as a file and flags row by row is held to the same standard:
 * only the accepted rows reach the ledger.
 */
@QuarkusTest
@TestSecurity(user = PrudentTest.ALICE)
class ImportFailureMatrixTest {

  private static final UUID ALICE = UUID.fromString(PrudentTest.ALICE);
  private static final UUID BOB = UUID.fromString(PrudentTest.BOB);

  /** Words of the synthetic statements that must never come back in an answer or a log line. */
  private static final List<String> NEVER_ECHOED =
      List.of("TESTOWY", "TESTOWA", "TESTOWE", "SKLEP", "BLIK", "DOP.", "PŁATNOŚĆ", "PRZYKŁADOWA", "ref:");

  @jakarta.inject.Inject jakarta.persistence.EntityManager entityManager;

  private UUID erste;
  private UUID savings;
  private UUID unnumbered;
  private UUID inactive;
  private UUID bobs;
  private UUID expenseCategory;
  private UUID incomeCategory;
  private final CapturedLog log = new CapturedLog();

  @BeforeEach
  void seed() {
    PrudentTest.reset();
    // The statement's own account holds PLN and EUR, so a foreign card payment is refused for its
    // own sake and not because the account could not take it.
    erste = PrudentTest.seedAccount(PrudentTest.ALICE, "Erste", "PLN", "EUR");
    savings = PrudentTest.seedAccount(PrudentTest.ALICE, "Savings", "PLN");
    unnumbered = PrudentTest.seedAccount(PrudentTest.ALICE, "No number", "PLN");
    inactive = PrudentTest.seedAccount(PrudentTest.ALICE, "Retired", "PLN");
    bobs = PrudentTest.seedAccount(PrudentTest.BOB, "Bob's", "PLN");
    expenseCategory = PrudentTest.seedCategory(PrudentTest.ALICE, "Spending");
    incomeCategory = PrudentTest.seedCategory(PrudentTest.ALICE, "Income");
    UUID bobsCategory = PrudentTest.seedCategory(PrudentTest.BOB, "Bob's category");
    QuarkusTransaction.requiringNew()
        .run(
            () -> {
              AccountEntity.<AccountEntity>findById(erste).accountNumber = ImportTestSupport.Erste.ACCOUNT;
              AccountEntity.<AccountEntity>findById(savings).accountNumber = ImportTestSupport.Erste.OTHER_ACCOUNT;
              AccountEntity.<AccountEntity>findById(inactive).isActive = false;
              // Another user may hold the same number: ownership, not the number, decides.
              AccountEntity.<AccountEntity>findById(bobs).accountNumber = ImportTestSupport.Erste.ACCOUNT;
            });
    // Existing ledger data of both users, so that "nothing changed" has something to change.
    PrudentTest.seedRecord(PrudentTest.ALICE, erste, expenseCategory, -1_234L, "PLN");
    PrudentTest.seedRecord(PrudentTest.BOB, bobs, bobsCategory, -999L, "PLN");
    PrudentTest.seedImportSession(PrudentTest.BOB, ImportState.PARSED, java.time.Instant.now().plusSeconds(3600));
    log.attach();
  }

  @AfterEach
  void detach() {
    log.detach();
  }

  // --- the database, as one comparable value -----------------------------------------------------

  /** Everything a refused import could have touched, for both users. */
  record Snapshot(
      long sessions, long rows, List<String> sessionStates, List<String> records, List<String> accounts) {}

  Snapshot snapshot() {
    return QuarkusTransaction.requiringNew()
        .call(
            () -> {
              List<String> records = new ArrayList<>();
              for (RecordEntity r : RecordEntity.<RecordEntity>listAll()) {
                records.add(
                    String.join(
                        "|", r.id.toString(), r.userId.toString(), r.accountId.toString(),
                        String.valueOf(r.amountMinor), r.currency, String.valueOf(r.date),
                        String.valueOf(r.categoryId), String.valueOf(r.importFingerprint),
                        String.valueOf(r.importOccurrence), String.valueOf(r.title),
                        String.valueOf(r.payee), String.valueOf(r.note)));
              }
              List<String> accounts = new ArrayList<>();
              for (AccountEntity a : AccountEntity.<AccountEntity>listAll()) {
                List<String> balances = new ArrayList<>();
                a.balances.forEach(b -> balances.add(b.currency + "=" + b.amountMinor));
                Collections.sort(balances);
                accounts.add(
                    String.join(
                        "|", a.id.toString(), a.userId.toString(), a.name, String.valueOf(a.isActive),
                        String.valueOf(a.accountNumber), balances.toString(),
                        String.valueOf(RecordEntity.netByAccount(a.userId, a.id))));
              }
              List<String> states = new ArrayList<>();
              for (ImportSessionEntity s : ImportSessionEntity.<ImportSessionEntity>listAll()) {
                states.add(s.id + "|" + s.userId + "|" + s.state + "|" + s.acceptedRows + "|" + s.accountId);
              }
              Collections.sort(records);
              Collections.sort(accounts);
              Collections.sort(states);
              return new Snapshot(ImportSessionEntity.count(), ImportRowEntity.count(), states, records, accounts);
            });
  }

  // --- the log, captured --------------------------------------------------------------------------

  /** Every line the server logs while a case runs, with the messages of any exception behind it. */
  static final class CapturedLog extends Handler {
    final List<String> lines = Collections.synchronizedList(new ArrayList<>());

    void attach() {
      setLevel(java.util.logging.Level.ALL);
      Logger.getLogger("").addHandler(this);
    }

    void detach() {
      Logger.getLogger("").removeHandler(this);
    }

    @Override
    public void publish(LogRecord record) {
      StringBuilder line = new StringBuilder();
      try {
        line.append(new java.util.logging.SimpleFormatter().formatMessage(record));
      } catch (RuntimeException unformattable) {
        line.append(record.getMessage());
      }
      for (Throwable t = record.getThrown(); t != null; t = t.getCause()) {
        line.append(" | ").append(t.getClass().getName()).append(": ").append(t.getMessage());
      }
      lines.add(line.toString());
    }

    @Override
    public void flush() {}

    @Override
    public void close() {}
  }

  // --- what must not appear -------------------------------------------------------------------------

  /** The free-text values of a statement: a whole field of six or more characters. */
  private static Set<String> tokens(byte[] content) {
    Set<String> tokens = new HashSet<>();
    if (content.length > 1_000_000) {
      return tokens;
    }
    for (String token : new String(content, StandardCharsets.UTF_8).split("[,;\t\n\r\"|]")) {
      String trimmed = token.trim();
      if (trimmed.length() >= 6 && trimmed.length() <= 200) {
        tokens.add(trimmed);
      }
    }
    return tokens;
  }

  /** Tokens a log line may legitimately hold: ids, timestamps and durations are not statement data. */
  private static final java.util.regex.Pattern LOG_SAFE =
      java.util.regex.Pattern.compile(
          "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}" // a UUID
              + "|\\d{4}-\\d{2}-\\d{2}[T ]\\d{2}:\\d{2}:\\d{2}(?:[.,]\\d+)?(?:Z|[+-]\\d{2}:?\\d{2})?" // a time
              + "|\\d+(?:\\.\\d+)? ?(?:ms|s|MB|KB|B)\\b" // a duration or size
              + "|\\(statement\\.[a-z_]+\\)");

  /**
   * The numbers of a statement that must not reach a log: every field's digits when the field is a
   * date, an account number or an amount of four or more digits (stripped of spaces, dots, dashes
   * and the sign, so {@code 12 3456} and {@code 123456} are one value), and every amount in both
   * its comma and its dot spelling whatever its size, since a line that says {@code 0,00} or
   * {@code 7.10} has quoted a figure of the file. Sequence numbers (short pure-digit fields) are
   * left out: they are row numbers in disguise, and rows are named in messages on purpose.
   */
  private static Set<String> numbers(byte[] content) {
    Set<String> numbers = new HashSet<>();
    if (content.length > 1_000_000) {
      return numbers;
    }
    for (String field : new String(content, StandardCharsets.UTF_8).split("[,;\t\n\r\"|]")) {
      String trimmed = field.trim();
      String digits = trimmed.replaceAll("[^0-9]", "");
      if (trimmed.matches("\\d{1,7}")) {
        continue; // a sequence number or a row-sized figure
      }
      if (digits.length() >= 4 && trimmed.length() <= 200) {
        numbers.add(digits);
      }
    }
    // Amounts are the comma-separated pairs "12" "34" split above, so read them from the text.
    java.util.regex.Matcher amount =
        java.util.regex.Pattern.compile("(?<![\\d.])(-?\\d{1,11}),(\\d{2})(?!\\d)")
            .matcher(new String(content, StandardCharsets.UTF_8));
    while (amount.find()) {
      numbers.add(amount.group(1).replace("-", "") + "," + amount.group(2));
      numbers.add(amount.group(1).replace("-", "") + "." + amount.group(2));
    }
    return numbers;
  }

  /** The first leak of the statement's text or numbers in {@code texts}, or null. */
  static String firstLeak(byte[] content, List<String> texts) {
    Set<String> tokens = tokens(content);
    Set<String> numbers = numbers(content);
    for (String text : texts) {
      for (String word : NEVER_ECHOED) {
        if (text.contains(word)) {
          return "'" + word + "' leaked: " + abbreviate(text);
        }
      }
      for (String token : tokens) {
        if (text.contains(token)) {
          return "a statement value leaked: " + abbreviate(text);
        }
      }
      String scrubbed = LOG_SAFE.matcher(text).replaceAll(" ");
      String alphanumeric = scrubbed.replaceAll("[^A-Za-z0-9]", "");
      for (String number : numbers) {
        boolean amount = number.matches("\\d+[,.]\\d{2}");
        boolean found =
            amount
                ? java.util.regex.Pattern.compile("(?<![\\d.,])-?" + java.util.regex.Pattern.quote(number) + "(?!\\d)")
                    .matcher(scrubbed).find()
                : alphanumeric.contains(number);
        if (found) {
          return "a number of the statement leaked: " + abbreviate(text);
        }
      }
    }
    return null;
  }

  private void assertNoStatementText(byte[] content, String answer) {
    List<String> everything = new ArrayList<>();
    everything.add(answer);
    synchronized (log.lines) {
      everything.addAll(log.lines);
    }
    String leak = firstLeak(content, everything);
    assertTrue(leak == null, leak);
  }

  private static String abbreviate(String text) {
    return text.length() > 300 ? text.substring(0, 300) + "..." : text;
  }

  private UUID destination(Destination destination) {
    switch (destination) {
      case ERSTE:
        return erste;
      case NONE:
        return null;
      case OTHER_NUMBER:
        return savings;
      case UNNUMBERED:
        return unnumbered;
      case WITHOUT_PLN:
        QuarkusTransaction.requiringNew()
            .run(
                () -> {
                  AccountEntity account = AccountEntity.findById(erste);
                  account.balances.clear();
                  account.balances.add(new AccountBalance("EUR", 0L));
                });
        return erste;
      case INACTIVE:
        return inactive;
      case SOMEONE_ELSES:
        return bobs;
      case UNKNOWN_ID:
        return UUID.randomUUID();
      default:
        throw new IllegalArgumentException(destination.name());
    }
  }

  // --- whole-file refusals --------------------------------------------------------------------------

  static Stream<Arguments> refusals() {
    return ImportFailureCatalogue.refusals().stream().map(c -> Arguments.of(c.name(), c));
  }

  @ParameterizedTest(name = "{0}")
  @MethodSource("refusals")
  void aRefusedStatement_isActionableAndWritesNothing(String name, Refusal refusal) throws Exception {
    UUID account = destination(refusal.destination());
    Snapshot before = snapshot();

    Response response = uploadErste(refusal.content(), account);

    ZenError refused = error(response, refusal.status());
    assertEquals("invalid", refused.getCode(), name);
    assertEquals(refusal.expectedMessage(), refused.getMessage(), name);
    assertTrue(
        refused.getMessage().matches("[A-Za-z0-9 ,.()_]*"),
        "only a rule code, row numbers and fixed words: " + refused.getMessage());
    assertFalse(response.asString().contains("0000"), "an account number or amount in the body");
    assertNoStatementText(refusal.content(), response.asString());
    assertEquals(before, snapshot(), "a refused statement changed the database: " + name);

    // Nothing is left half-done: a good statement is accepted straight away.
    QuarkusTransaction.requiringNew()
        .run(
            () -> {
              AccountEntity restored = AccountEntity.findById(erste);
              restored.balances.clear();
              restored.balances.add(new AccountBalance("PLN", 0L));
            });
    UUID good = destination(Destination.ERSTE);
    ImportSession next = session(uploadErste(ImportTestSupport.Erste.baseBytes(), good));
    assertEquals(5, next.getAcceptedRows());
  }

  // --- statements flagged row by row ----------------------------------------------------------------

  static Stream<Arguments> flagged() {
    return ImportFailureCatalogue.flagged().stream().map(c -> Arguments.of(c.name(), c));
  }

  @ParameterizedTest(name = "{0}")
  @MethodSource("flagged")
  void aFlaggedRow_isListedWithItsRule_andOnlyTheRestReachesTheLedger(String name, Flagged flagged)
      throws Exception {
    Snapshot before = snapshot();
    Response response = uploadErste(flagged.content(), erste);
    ImportSession parsed = session(response);

    assertEquals(flagged.codes().size(), parsed.getRowsCount(), name);
    long expectedAccepted = flagged.codes().stream().filter(java.util.Objects::isNull).count();
    assertEquals(expectedAccepted, parsed.getAcceptedRows(), name);
    assertEquals(flagged.codes().size() - expectedAccepted, parsed.getRejectedRows(), name);
    for (int i = 0; i < flagged.codes().size(); i++) {
      ImportRow row = parsed.getRows(i);
      String code = flagged.codes().get(i);
      assertEquals(i + 1, row.getRowNumber());
      if (code == null) {
        assertEquals(ImportRowStatus.IMPORT_ROW_STATUS_ACCEPTED, row.getStatus(), name + " row " + (i + 1));
        assertEquals("", row.getRejectionCode());
      } else {
        assertEquals(ImportRowStatus.IMPORT_ROW_STATUS_REJECTED, row.getStatus(), name + " row " + (i + 1));
        assertEquals(code, row.getRejectionCode(), name + " row " + (i + 1));
        assertFalse(row.hasDescription() || row.hasCounterparty() || row.hasCounterpartyAccount()
            || row.hasExternalId() || row.hasAmountMinor(), "a flagged row keeps no content");
        assertFalse(row.hasCategoryId());
      }
    }
    // The ledger is untouched by a parse.
    Snapshot parsedState = snapshot();
    assertEquals(before.records(), parsedState.records());
    assertEquals(before.accounts(), parsedState.accounts());

    // Preview and commit: exactly the accepted rows are written, none of the flagged ones.
    session(preview(parsed.getId(), erste));
    defaults(parsed.getId(), expenseCategory, incomeCategory);
    long recordsBefore = RecordEntity.count();
    ImportSession done = session(commit(parsed.getId(), (int) expectedAccepted));
    assertEquals(ImportSessionState.IMPORT_SESSION_STATE_COMMITTED, done.getState());
    assertEquals(expectedAccepted, done.getCommittedWritten(), name);
    assertEquals(recordsBefore + expectedAccepted, RecordEntity.count(), name);
    long expectedMinor = 0;
    for (int i = 0; i < flagged.codes().size(); i++) {
      if (flagged.codes().get(i) == null) {
        expectedMinor += parsed.getRows(i).getAmountMinor();
      }
    }
    long written =
        QuarkusTransaction.requiringNew()
            .call(() -> RecordEntity.netByAccount(ALICE, erste).getOrDefault("PLN", 0L));
    assertEquals(-1_234L + expectedMinor, written, name + ": the balance moved by exactly the accepted rows");
  }

  // --- the same statement, however it arrives -------------------------------------------------------

  private ImportSession previewed(byte[] file) throws Exception {
    ImportSession parsed = session(uploadErste(file, erste));
    ImportSession view = session(preview(parsed.getId(), erste));
    defaults(parsed.getId(), expenseCategory, incomeCategory);
    return view;
  }

  private long erstePln() {
    return QuarkusTransaction.requiringNew()
        .call(() -> RecordEntity.netByAccount(ALICE, erste).getOrDefault("PLN", 0L));
  }

  private static final long BASE_NET = -710 - 2500 + 10000 - 300 - 100;

  @Test
  void theSameStatementImportedTwice_hasItsEffectOnTheLedgerOnce() throws Exception {
    ImportSession first = previewed(ImportTestSupport.Erste.baseBytes());
    assertEquals(5, session(commit(first.getId(), 5)).getCommittedWritten());
    assertEquals(-1_234L + BASE_NET, erstePln());
    Snapshot afterFirst = snapshot();

    ImportSession second = previewed(ImportTestSupport.Erste.baseBytes());
    assertEquals(0, second.getAcceptedRows());
    assertEquals(5, second.getDuplicateRows());
    ImportSession done = session(commit(second.getId(), 0));
    assertEquals(0, done.getCommittedWritten());
    assertEquals(afterFirst.records(), snapshot().records(), "the second import wrote nothing");
    assertEquals(-1_234L + BASE_NET, erstePln());
  }

  @Test
  void twoTabsThatBothPreviewedBeforeEitherCommitted_writeTheLedgerOnce() throws Exception {
    ImportSession tabA = previewed(ImportTestSupport.Erste.baseBytes());
    ImportSession tabB = previewed(ImportTestSupport.Erste.baseBytes());
    assertEquals(5, tabB.getAcceptedRows(), "nothing was in the ledger when tab B previewed");

    assertEquals(5, session(commit(tabA.getId(), 5)).getCommittedWritten());
    ImportSession b = session(commit(tabB.getId(), 5));

    assertEquals(0, b.getCommittedWritten(), "the second tab's rows were already imported");
    assertEquals(5, b.getCommittedAlreadyImported());
    assertEquals(-1_234L + BASE_NET, erstePln());
    assertEquals(1 + 1 + 5, RecordEntity.count(), "Alice's seeded record, Bob's, and five imported");
  }

  @Test
  void aCommitRepeatedAfterALostResponse_answersTheSameAndWritesNothing() throws Exception {
    ImportSession view = previewed(ImportTestSupport.Erste.baseBytes());
    ImportSession first = session(commit(view.getId(), 5));
    Snapshot after = snapshot();

    ImportSession again = session(commit(view.getId(), 5));

    assertEquals(first.getCommittedWritten(), again.getCommittedWritten());
    assertEquals(after.records(), snapshot().records());
    error(commit(view.getId(), 4), 409);
    assertEquals(after.records(), snapshot().records());
  }

  @Test
  void overlappingStatements_withOtherSequenceNumbers_writeEachOperationOnce() throws Exception {
    List<String[]> all = ImportTestSupport.Erste.base();
    List<String[]> older = new ArrayList<>(java.util.Arrays.asList(all.get(0), all.get(3), all.get(4), all.get(5)));
    List<String[]> newer = new ArrayList<>(java.util.Arrays.asList(all.get(0), all.get(1), all.get(2), all.get(3)));
    // The newer export numbers every row differently, as a rank from its own newest row would.
    for (int i = 1; i < newer.size(); i++) {
      newer.set(i, newer.get(i).clone());
      newer.get(i)[7] = String.valueOf(100 + i);
    }
    ImportSession first = previewed(ImportTestSupport.Erste.bytes(ImportTestSupport.Erste.lines(older)));
    assertEquals(3, first.getAcceptedRows());
    session(commit(first.getId(), 3));

    ImportSession second = previewed(ImportTestSupport.Erste.bytes(ImportTestSupport.Erste.lines(newer)));
    assertEquals(2, second.getAcceptedRows(), "the shared own-account transfer is recognised");
    assertEquals(1, second.getDuplicateRows());
    session(commit(second.getId(), 2));

    assertEquals(-1_234L + BASE_NET, erstePln(), "the five operations of the base statement, once each");
  }

  @Test
  void identicalRowsInOneStatement_areBothImported_andNeitherAgain() throws Exception {
    List<String[]> rows = new ArrayList<>();
    rows.add(ImportTestSupport.Erste.summary());
    rows.add(ImportTestSupport.Erste.card("06-03-2026", "06-03-2026", "SKLEP D TESTOWY", "-1,00", 1));
    rows.add(ImportTestSupport.Erste.card("06-03-2026", "06-03-2026", "SKLEP D TESTOWY", "-1,00", 2));
    byte[] file = ImportTestSupport.Erste.bytes(ImportTestSupport.Erste.lines(rows));

    ImportSession first = previewed(file);
    assertEquals(2, first.getAcceptedRows(), "two coffees on one day are two operations");
    session(commit(first.getId(), 2));
    assertEquals(-1_234L - 200, erstePln());

    ImportSession again = previewed(file);
    assertEquals(0, again.getAcceptedRows());
    assertEquals(2, again.getDuplicateRows());
    session(commit(again.getId(), 0));
    assertEquals(-1_234L - 200, erstePln());
  }

  @Test
  void aStatementOfOnlyFlaggedRows_previewsAndCommitsAsNothing() throws Exception {
    byte[] file =
        ImportTestSupport.Erste.mapRows(
            r -> {
              String[] copy = r.clone();
              if (r[0].matches("\\d{2}-\\d{2}-\\d{4}")) {
                copy[2] = "Operacja nieznana TEST";
              }
              return copy;
            });
    ImportSession parsed = session(uploadErste(file, erste));
    assertEquals(0, parsed.getAcceptedRows());
    assertEquals(5, parsed.getRejectedRows());
    session(preview(parsed.getId(), erste));
    Snapshot before = snapshot();

    ImportSession done = session(commit(parsed.getId(), 0));

    assertEquals(0, done.getCommittedWritten());
    assertEquals(before.records(), snapshot().records());
    assertEquals(before.accounts(), snapshot().accounts());
  }

  @Test
  void aBenignVariation_isTheSameStatement_andNotAFalseAlarm() throws Exception {
    // Every field in quotes is plain RFC 4180 and carries the same data.
    Flagged quoted =
        ImportFailureCatalogue.flagged().stream()
            .filter(f -> f.name().contains("every field quoted"))
            .findFirst()
            .orElseThrow();
    ImportSession viaQuotes = session(uploadErste(quoted.content(), erste));
    ImportSession plain = session(uploadErste(ImportTestSupport.Erste.baseBytes(), erste));
    assertEquals(plain.getRowsCount(), viaQuotes.getRowsCount());
    for (int i = 0; i < plain.getRowsCount(); i++) {
      assertEquals(plain.getRows(i).getDescription(), viaQuotes.getRows(i).getDescription());
      assertEquals(plain.getRows(i).getAmountMinor(), viaQuotes.getRows(i).getAmountMinor());
      assertEquals(plain.getRows(i).getTransactionDate(), viaQuotes.getRows(i).getTransactionDate());
    }
  }

  // --- the matrix's own instruments, shown to work --------------------------------------------------

  @Test
  void theLogCaptureSeesWhatTheServerLogs_andTheLeakCheckFiresOnAStatementValue() {
    org.jboss.logging.Logger.getLogger("prudent.imports.probe").error("probe line SKLEP B TESTOWY");
    assertTrue(log.lines.stream().anyMatch(l -> l.contains("probe line")), "the capture sees server logging");

    byte[] content = ImportTestSupport.Erste.baseBytes();
    org.junit.jupiter.api.Assertions.assertThrows(
        AssertionError.class, () -> assertNoStatementText(content, "the answer quotes SKLEP B TESTOWY"));
    org.junit.jupiter.api.Assertions.assertThrows(
        AssertionError.class, () -> assertNoStatementText(content, "ok"), "the captured log line above leaks");
  }

  @Test
  void theLeakCheckCatchesANumberOfTheFileInAnyFormAndLetsIdsAndTimesThrough() {
    byte[] content = ImportTestSupport.Erste.baseBytes();
    String account = "00 0000 0000 0000 0000 0000 0010";
    // The plants a reviewer found missing: an account number without its spaces, an amount that
    // belongs to an amount.zero row, a figure in the dot spelling, a date written without dashes.
    for (String leak :
        new String[] {
          "rejected account 00000000000000000000000010 on row 3",
          "amount.zero for 0,00 on row 3",
          "row 1 amount 7.10",
          "row 4 booked 08032026",
          "account " + account,
          "amount 100,00 (row 3)",
        }) {
      org.junit.jupiter.api.Assertions.assertNotNull(
          firstLeak(content, List.of(leak)), "not caught: " + leak);
    }
    for (String fine :
        new String[] {
          "The statement was rejected at row 3 (amount.zero).",
          "request 5f0c2a9e-1b2c-4d5e-8f90-123456789abc handled in 12 ms",
          "2026-11-15 10:11:12,345 WARN [prudent.imports] rows 1, 2 and 3 more (date.invalid)",
          "user 00000000-0000-0000-0000-0000000000a1 session 5f0c2a9e-1b2c-4d5e-8f90-123456789abc",
        }) {
      assertEquals(null, firstLeak(content, List.of(fine)), "a false alarm: " + fine);
    }
  }

  @Test
  void theSnapshotSeesEveryKindOfWrite() throws Exception {
    Snapshot before = snapshot();
    PrudentTest.seedRecord(PrudentTest.ALICE, erste, expenseCategory, -1L, "PLN");
    assertFalse(before.equals(snapshot()), "a record");
    before = snapshot();
    QuarkusTransaction.requiringNew().run(() -> AccountEntity.<AccountEntity>findById(erste).name = "Renamed");
    assertFalse(before.equals(snapshot()), "an account");
    before = snapshot();
    session(uploadErste(ImportTestSupport.Erste.baseBytes(), erste));
    assertFalse(before.equals(snapshot()), "a session and its rows");
    before = snapshot();
    PrudentTest.seedImportSession(PrudentTest.BOB, ImportState.PARSED, java.time.Instant.now().plusSeconds(60));
    assertFalse(before.equals(snapshot()), "another user's session");
  }
}
