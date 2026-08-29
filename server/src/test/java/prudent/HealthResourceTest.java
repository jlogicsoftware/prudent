package prudent;

import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.equalTo;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.google.protobuf.util.JsonFormat;
import io.quarkus.test.junit.QuarkusTest;
import io.restassured.response.Response;
import org.junit.jupiter.api.Test;
import zen.proto.v1.HealthStatus;
import zen.transport.ZenTransportFormat;

/**
 * Proves the dual-mode transport seam on Prudent's own {@link prudent.health.HealthResource}: one resource, one
 * framework proto model, two wire formats selected by {@code X-Zen-Transport}. This is also what
 * {@code task test:e2e} polls before driving the suite, and what a deploy's readiness check calls.
 */
@QuarkusTest
class HealthResourceTest {

  private static final String PATH = "/api/v1/health";

  @Test
  void jsonMode_returnsCanonicalProto3Json() throws Exception {
    Response resp = given().header(ZenTransportFormat.HEADER, "json").when().get(PATH).andReturn();

    assertEquals(200, resp.statusCode());
    assertTrue(
        resp.getContentType().startsWith("application/json"),
        "expected JSON content type, got " + resp.getContentType());
    assertEquals("json", resp.getHeader(ZenTransportFormat.HEADER));

    HealthStatus.Builder parsed = HealthStatus.newBuilder();
    JsonFormat.parser().merge(resp.getBody().asString(), parsed);
    assertEquals("ok", parsed.getStatus());
    assertEquals("prudent-server", parsed.getService());
    assertTrue(parsed.getTimestampMs() > 0);
  }

  @Test
  void protobufMode_returnsParseableBinary() throws Exception {
    Response resp =
        given().header(ZenTransportFormat.HEADER, "protobuf").when().get(PATH).andReturn();

    assertEquals(200, resp.statusCode());
    assertTrue(
        resp.getContentType().startsWith("application/x-protobuf"),
        "expected protobuf content type, got " + resp.getContentType());
    assertEquals("protobuf", resp.getHeader(ZenTransportFormat.HEADER));

    HealthStatus parsed = HealthStatus.parseFrom(resp.getBody().asByteArray());
    assertEquals("ok", parsed.getStatus());
    assertEquals("prudent-server", parsed.getService());
    assertTrue(parsed.getTimestampMs() > 0);
  }

  @Test
  void noHeader_defaultsToJson() {
    given().when().get(PATH).then().statusCode(200).header(ZenTransportFormat.HEADER, equalTo("json"));
  }
}
