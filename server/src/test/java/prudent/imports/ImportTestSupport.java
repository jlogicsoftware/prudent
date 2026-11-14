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

  /** Records a commit instead of refusing it, optionally slowly to widen a race window. */
  static final class RecordingCommitter extends UnavailableImportCommitter {
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
    QuarkusMock.installMockForType(committer, UnavailableImportCommitter.class);
    return committer;
  }
}
