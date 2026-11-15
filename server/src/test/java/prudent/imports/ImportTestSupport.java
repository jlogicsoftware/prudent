package prudent.imports;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.google.protobuf.ByteString;
import com.google.protobuf.Message;
import io.quarkus.narayana.jta.QuarkusTransaction;
import io.quarkus.test.junit.QuarkusMock;
import io.restassured.response.Response;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.UUID;
import prudent.PrudentTest;
import prudent.proto.v1.CommitImportSessionRequest;
import prudent.proto.v1.CreateImportSessionRequest;
import prudent.proto.v1.ImportSession;
import prudent.proto.v1.ListImportSessionsResponse;
import prudent.proto.v1.PreviewImportSessionRequest;
import zen.proto.v1.ZenError;

/** HTTP helpers shared by the import suites; every statement and name in them is synthetic. */
final class ImportTestSupport {

  static final String SESSIONS = "/api/v1/import-sessions";

  private ImportTestSupport() {}

  /** Plain statement text for {@link TestStatementImporter}: one good row, one more. */
  static String statement(String firstLine, String... rowDescriptions) {
    List<String> lines = new ArrayList<>();
    lines.add(firstLine);
    int day = 1;
    for (String description : rowDescriptions) {
      lines.add("2026-11-" + String.format("%02d", day++) + ";-" + (100 + day) + ";" + description + ";x");
    }
    lines.add("");
    return String.join("\n", lines);
  }

  static Response post(String path, Message body) throws Exception {
    return PrudentTest.body(PrudentTest.request(PrudentTest.JSON), PrudentTest.JSON, body)
        .when()
        .post(path)
        .andReturn();
  }

  static Response upload(String content, UUID accountId) throws Exception {
    CreateImportSessionRequest.Builder request =
        CreateImportSessionRequest.newBuilder()
            .setFormatId(TestStatementImporter.FORMAT)
            .setContent(ByteString.copyFrom(content, StandardCharsets.UTF_8));
    if (accountId != null) {
      request.setAccountId(accountId.toString());
    }
    return post(SESSIONS, request.build());
  }

  /** Uploads {@code content} as an Erste statement, optionally for a destination account. */
  static Response uploadErste(byte[] content, UUID accountId) throws Exception {
    CreateImportSessionRequest.Builder request =
        CreateImportSessionRequest.newBuilder()
            .setFormatId(ImportFormatIds.ERSTE_PL_CSV)
            .setContent(ByteString.copyFrom(content));
    if (accountId != null) {
      request.setAccountId(accountId.toString());
    }
    return post(SESSIONS, request.build());
  }

  static Response discard(String id) throws Exception {
    return post(
        SESSIONS + "/" + id + "/discard",
        PreviewImportSessionRequest.getDefaultInstance());
  }

  static Response preview(String id, UUID accountId) throws Exception {
    PreviewImportSessionRequest.Builder request = PreviewImportSessionRequest.newBuilder();
    if (accountId != null) {
      request.setAccountId(accountId.toString());
    }
    return post(SESSIONS + "/" + id + "/preview", request.build());
  }

  static Response commit(String id, int confirmed) throws Exception {
    return post(
        SESSIONS + "/" + id + "/commit",
        CommitImportSessionRequest.newBuilder().setConfirmedAcceptedRows(confirmed).build());
  }

  /** Sets the session's default categories, so every row has one without deciding each. */
  static void defaults(String id, UUID expenseCategory, UUID incomeCategory) throws Exception {
    session(
        post(
            SESSIONS + "/" + id + "/defaults",
            prudent.proto.v1.SetImportDefaultsRequest.newBuilder()
                .setDefaultExpenseCategoryId(expenseCategory.toString())
                .setDefaultIncomeCategoryId(incomeCategory.toString())
                .build()));
  }

  static Response get(String id) {
    return PrudentTest.request(PrudentTest.JSON).when().get(SESSIONS + "/" + id).andReturn();
  }

  static ImportSession session(Response response) throws Exception {
    assertTrue(response.statusCode() < 300, response.asString());
    return PrudentTest.decode(PrudentTest.JSON, response, ImportSession.newBuilder()).build();
  }

  static ZenError error(Response response, int status) throws Exception {
    assertEquals(status, response.statusCode(), response.asString());
    return PrudentTest.decode(PrudentTest.JSON, response, ZenError.newBuilder()).build();
  }

  static ListImportSessionsResponse list(String query) throws Exception {
    Response response =
        PrudentTest.request(PrudentTest.JSON).when().get(SESSIONS + query).andReturn();
    assertEquals(200, response.statusCode(), response.asString());
    return PrudentTest.decode(
            PrudentTest.JSON, response, ListImportSessionsResponse.newBuilder())
        .build();
  }

  /** Counts rows of an entity in a transaction of its own. */
  static long count(jakarta.persistence.EntityManager entityManager, String entity) {
    return QuarkusTransaction.requiringNew()
        .call(
            () ->
                ((Number)
                        entityManager
                            .createQuery("select count(e) from " + entity + " e")
                            .getSingleResult())
                    .longValue());
  }

  /** Records a commit and answers it without writing, optionally slowly to widen a race window. */
  static final class RecordingCommitter extends LedgerImportCommitter {
    final List<List<ImportRowEntity>> calls = Collections.synchronizedList(new ArrayList<>());
    private final long pauseMillis;

    RecordingCommitter(long pauseMillis) {
      this.pauseMillis = pauseMillis;
    }

    @Override
    public CommitResult commit(ImportSessionEntity session, List<ImportRowEntity> accepted) {
      calls.add(new ArrayList<>(accepted));
      try {
        Thread.sleep(pauseMillis);
      } catch (InterruptedException interrupted) {
        Thread.currentThread().interrupt();
        throw new IllegalStateException(interrupted);
      }
      return new CommitResult(accepted.size(), 0);
    }
  }

  static RecordingCommitter installRecordingCommitter(long pauseMillis) {
    RecordingCommitter committer = new RecordingCommitter(pauseMillis);
    QuarkusMock.installMockForType(committer, LedgerImportCommitter.class);
    return committer;
  }

  /**
   * Synthetic Erste Polska statements for the failure and drift suites (ADR-094), built in memory
   * from nine-field rows so a test can change one field, one line or the bytes. Every name,
   * merchant and account is invented, as the contract's fixtures are; nothing here is a copy of a
   * real statement.
   */
  static final class Erste {

    /** The statement's own account in its stored (normal) form, and as the summary writes it. */
    static final String ACCOUNT = "00000000000000000000000001";

    static final String OTHER_ACCOUNT = "00000000000000000000000002";

    private Erste() {}

    /** The summary row's nine fields; field 3 is the account behind an apostrophe. */
    static String[] summary() {
      return new String[] {
        "2026-11-14",
        "01-01-2026",
        "'00 0000 0000 0000 0000 0000 0001",
        "JAN TESTOWY UL. PRZYK\u0141ADOWA 1/2 00-000 TESTOWO",
        "PLN",
        "0,00",
        "50,00",
        "999",
        ""
      };
    }

    /** A transaction row's nine fields. The balance is a fixed figure the importer never reads. */
    static String[] tx(
        String booking, String date, String description, String counterparty, String account,
        String amount, int sequence) {
      return new String[] {
        booking, date, description, counterparty, account, amount, "10,00",
        String.valueOf(sequence), ""
      };
    }

    static String[] card(String booking, String date, String merchant, String amount, int sequence) {
      String embedded = amount.replace("-", "").replace(",", ".");
      return tx(
          booking, date,
          "DOP. MC 000000******0000 P\u0141ATNO\u015a\u0106 KART\u0104 " + embedded + " PLN " + merchant,
          "", "", amount, sequence);
    }

    static String[] blik(String date, String merchant, String account, String amount, int sequence) {
      return tx(date, date, "Zakup BLIK " + merchant + " ref:00000000001", merchant, account, amount, sequence);
    }

    static String[] ownTransfer(String date, String account, String amount, int sequence) {
      return tx(
          date, date, ErsteStatementImporter.OWN_TRANSFER_DESCRIPTION,
          "FIRMA TESTOWA JAN TESTOWY UL. PRZYK\u0141ADOWA 1/2 00-000 TESTOWO WOJ. TESTOWE",
          account, amount, sequence);
    }

    /**
     * The valid statement every mutation starts from: the summary row and five rows that between
     * them hold each description shape, a booking date after the transaction date, an own-account
     * transfer and a sequence of 1 to 5. Row {@code n} of the importer is element {@code n} here.
     */
    static List<String[]> base() {
      List<String[]> rows = new ArrayList<>();
      rows.add(summary());
      rows.add(card("12-03-2026", "10-03-2026", "SKLEP A TESTOWY", "-7,10", 1));
      rows.add(blik("09-03-2026", "SKLEP B TESTOWY", "00 0000 0000 0000 0000 0000 0010", "-25,00", 2));
      rows.add(ownTransfer("08-03-2026", "00 0000 0000 0000 0000 0000 0002", "100,00", 3));
      rows.add(card("08-03-2026", "07-03-2026", "SKLEP C TESTOWY", "-3,00", 4));
      rows.add(card("06-03-2026", "06-03-2026", "SKLEP D TESTOWY", "-1,00", 5));
      return rows;
    }

    /** One CSV line: a field is quoted exactly when it holds a comma or a quote, as the bank does. */
    static String line(String... fields) {
      StringBuilder line = new StringBuilder();
      for (int i = 0; i < fields.length; i++) {
        if (i > 0) {
          line.append(',');
        }
        String field = fields[i] == null ? "" : fields[i];
        if (field.indexOf(',') >= 0 || field.indexOf('"') >= 0) {
          line.append('"').append(field.replace("\"", "\"\"")).append('"');
        } else {
          line.append(field);
        }
      }
      return line.toString();
    }

    static List<String> lines(List<String[]> rows) {
      return rows.stream().map(Erste::line).collect(java.util.stream.Collectors.toCollection(ArrayList::new));
    }

    static List<String> baseLines() {
      return lines(base());
    }

    /** The lines as the bank writes a file: LF after every line, the last included. */
    static byte[] bytes(List<String> lines) {
      return (String.join("\n", lines) + "\n").getBytes(StandardCharsets.UTF_8);
    }

    static byte[] baseBytes() {
      return bytes(baseLines());
    }

    /** The base statement with {@code field} (0-based) of transaction row {@code row} (1-based) set. */
    static byte[] withField(int row, int field, String value) {
      List<String[]> rows = base();
      rows.get(row)[field] = value;
      return bytes(lines(rows));
    }

    /** The base statement with {@code field} (0-based) of the summary row set. */
    static byte[] withSummaryField(int field, String value) {
      return withField(0, field, value);
    }

    /** The base statement's text with every field of every line passed through {@code change}. */
    static byte[] mapRows(java.util.function.UnaryOperator<String[]> change) {
      List<String[]> rows = base();
      rows.replaceAll(change);
      return bytes(lines(rows));
    }

    /** The base statement's text, for byte-level edits. */
    static String baseText() {
      return new String(baseBytes(), StandardCharsets.UTF_8);
    }

    /** The summary row and {@code count} one-zloty card payments on distinct sequence numbers. */
    static byte[] manyCards(int count) {
      List<String[]> rows = new ArrayList<>();
      rows.add(summary());
      for (int i = 1; i <= count; i++) {
        rows.add(card("06-03-2026", "06-03-2026", "SKLEP TESTOWY " + i, "-1,00", i));
      }
      return bytes(lines(rows));
    }
  }
}
