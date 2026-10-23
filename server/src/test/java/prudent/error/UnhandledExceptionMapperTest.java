package prudent.error;

import static io.restassured.RestAssured.given;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.google.protobuf.util.JsonFormat;
import io.quarkus.test.junit.QuarkusTest;
import io.restassured.response.Response;
import java.util.List;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.logging.Handler;
import java.util.logging.Level;
import java.util.logging.LogRecord;
import java.util.logging.Logger;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import zen.proto.v1.ZenError;

/**
 * An unhandled failure answers with the fixed {@code ZenError}, names its request in the response,
 * and leaves exactly one log line that says where and what — and not the data.
 */
@QuarkusTest
class UnhandledExceptionMapperTest {

  private static final String BASE = "/test-support/failures";

  private final List<String> logged = new CopyOnWriteArrayList<>();
  private final Logger logger = Logger.getLogger(UnhandledExceptionMapper.class.getName());
  private final Handler capture =
      new Handler() {
        @Override
        public void publish(LogRecord record) {
          if (record.getLevel().intValue() >= Level.SEVERE.intValue()) {
            logged.add(new java.util.logging.SimpleFormatter().formatMessage(record));
          }
        }

        @Override
        public void flush() {}

        @Override
        public void close() {}
      };

  @BeforeEach
  void attach() {
    logger.addHandler(capture);
  }

  @AfterEach
  void detach() {
    logger.removeHandler(capture);
  }

  @Test
  void anUnmappedFailureAnswersWithAFixedBodyAndTheRequestId() throws Exception {
    Response resp = given().header("X-Request-ID", "trace-42").get(BASE + "/database").andReturn();

    assertEquals(500, resp.statusCode());
    assertEquals("trace-42", resp.getHeader("X-Request-ID"));
    ZenError.Builder body = ZenError.newBuilder();
    JsonFormat.parser().merge(resp.getBody().asString(), body);
    assertEquals("internal_error", body.getCode());
    assertEquals("Something went wrong. Please try again.", body.getMessage());
    assertFalse(resp.getBody().asString().contains("12345.67"));
  }

  @Test
  void theLogLineNamesTheRequestTheHandlerAndTheSqlStateButNotTheRow() {
    given().header("X-Request-ID", "trace-43").get(BASE + "/database?amount=999.99");

    assertEquals(1, logged.size(), logged.toString());
    String line = logged.get(0);
    assertTrue(line.contains("request=trace-43"), line);
    assertTrue(line.contains("method=GET"), line);
    assertTrue(line.contains("handler=FailureProbeResource.database"), line);
    assertTrue(line.contains("status=500"), line);
    assertTrue(line.contains("sqlstate=23502"), line);
    assertFalse(line.contains("12345.67"), line);
    assertFalse(line.contains("Salary"), line);
    assertFalse(line.contains("999.99"), "the query string must not reach the log: " + line);
  }

  @Test
  void aRequestWithoutAnIdGetsOne() {
    Response resp = given().get(BASE + "/database").andReturn();
    assertEquals(36, resp.getHeader("X-Request-ID").length());
  }

  @Test
  void aForgedIdIsReplacedNotEchoed() {
    Response resp = given().header("X-Request-ID", "a b").get(BASE + "/database").andReturn();
    assertFalse(resp.getHeader("X-Request-ID").contains(" "));
    assertEquals(1, logged.size());
    assertTrue(logged.get(0).contains("request=" + resp.getHeader("X-Request-ID")));
  }

  @Test
  void aWebServerErrorKeepsItsStatusAndIsLoggedWithoutItsMessage() {
    Response resp = given().get(BASE + "/web-server-error").andReturn();

    assertEquals(502, resp.statusCode());
    assertEquals(1, logged.size());
    assertTrue(logged.get(0).contains("status=502"), logged.get(0));
    assertFalse(logged.get(0).contains("12345.67"), logged.get(0));
  }

  @Test
  void aClientErrorKeepsItsStatusAndIsNotLogged() {
    Response resp = given().get(BASE + "/web-client-error").andReturn();

    assertEquals(418, resp.statusCode());
    assertTrue(logged.isEmpty(), logged.toString());
  }

  @Test
  void theIdIsOnSuccessfulResponsesToo() {
    Response resp = given().header("X-Request-ID", "ok-1").get("/api/v1/health").andReturn();
    assertEquals(200, resp.statusCode());
    assertEquals("ok-1", resp.getHeader("X-Request-ID"));
  }
}
