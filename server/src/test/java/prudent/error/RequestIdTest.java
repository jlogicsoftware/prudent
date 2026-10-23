package prudent.error;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

class RequestIdTest {

  @Test
  void adoptsABoringId() {
    RequestId id = new RequestId();
    id.adopt("abc-123_X.9");
    assertEquals("abc-123_X.9", id.value());
  }

  @ParameterizedTest
  @ValueSource(strings = {"", "has space", "line\nbreak", "forged\r\nlevel=ERROR", "ünï", "<script>"})
  void replacesAnIdThatCouldForgeALogLine(String hostile) {
    RequestId id = new RequestId();
    id.adopt(hostile);
    assertNotEquals(hostile, id.value());
    assertTrue(RequestId.ACCEPTABLE.matcher(id.value()).matches());
  }

  @Test
  void replacesAnOverlongId() {
    RequestId id = new RequestId();
    id.adopt("a".repeat(65));
    assertEquals(36, id.value().length());
  }

  @Test
  void mintsOneWhenNothingWasSupplied() {
    RequestId id = new RequestId();
    id.adopt(null);
    String first = id.value();
    assertEquals(first, id.value());
  }

  @Test
  void mintsLazilyWhenNothingAdoptedYet() {
    assertEquals(36, new RequestId().value().length());
  }
}
