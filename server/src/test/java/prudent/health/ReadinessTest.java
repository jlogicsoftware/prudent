package prudent.health;

import static io.restassured.RestAssured.given;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotEquals;

import com.google.protobuf.util.JsonFormat;
import io.quarkus.test.junit.QuarkusMock;
import io.quarkus.test.junit.QuarkusTest;
import io.restassured.response.Response;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import zen.proto.v1.HealthStatus;
import zen.proto.v1.ZenError;
import zen.transport.ZenTransportFormat;

/** {@code GET /api/v1/health/ready}: 200 with the database, 503 and a {@code ZenError} without. */
@QuarkusTest
class ReadinessTest {

  private static final String PATH = "/api/v1/health/ready";

  @ParameterizedTest
  @ValueSource(strings = {"json", "protobuf"})
  void readyWhenTheDatabaseAnswers(String mode) throws Exception {
    Response resp = given().header(ZenTransportFormat.HEADER, mode).get(PATH).andReturn();

    assertEquals(200, resp.statusCode());
    assertEquals(mode, resp.getHeader(ZenTransportFormat.HEADER));
    HealthStatus status;
    if (mode.equals("json")) {
      HealthStatus.Builder b = HealthStatus.newBuilder();
      JsonFormat.parser().merge(resp.getBody().asString(), b);
      status = b.build();
    } else {
      status = HealthStatus.parseFrom(resp.getBody().asByteArray());
    }
    assertEquals("ok", status.getStatus());
    assertEquals("prudent-server", status.getService());
  }

  @ParameterizedTest
  @ValueSource(strings = {"json", "protobuf"})
  void unavailableWhenTheDatabaseDoesNot(String mode) throws Exception {
    QuarkusMock.installMockForType(new DownProbe(), DatabaseProbe.class);

    Response resp = given().header(ZenTransportFormat.HEADER, mode).get(PATH).andReturn();

    assertEquals(503, resp.statusCode());
    ZenError error;
    if (mode.equals("json")) {
      ZenError.Builder b = ZenError.newBuilder();
      JsonFormat.parser().merge(resp.getBody().asString(), b);
      error = b.build();
    } else {
      error = ZenError.parseFrom(resp.getBody().asByteArray());
    }
    assertEquals("unavailable", error.getCode());
    assertEquals("The service is not ready.", error.getMessage());
    assertFalse(resp.getHeader("X-Request-ID").isBlank());
  }

  @Test
  void livenessIsUnaffectedByTheDatabase() {
    QuarkusMock.installMockForType(new DownProbe(), DatabaseProbe.class);

    assertEquals(200, given().get("/api/v1/health").statusCode());
  }

  @Test
  void needsNoSignIn() {
    assertNotEquals(401, given().get(PATH).statusCode());
  }

  /** A probe whose database is away. */
  static class DownProbe extends DatabaseProbe {
    DownProbe() {
      super(null);
    }

    @Override
    public boolean reachable() {
      return false;
    }
  }
}
