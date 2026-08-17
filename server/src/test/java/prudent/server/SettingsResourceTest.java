package prudent.server;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.security.TestSecurity;
import io.restassured.response.Response;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import prudent.proto.v1.Settings;
import prudent.proto.v1.UpdateSettingsRequest;
import prudent.server.settings.SettingsEntity;
import zen.proto.v1.ZenError;

/**
 * The settings singleton: {@code GET} and {@code PUT} in both transport modes, and the two
 * behaviours ADR-009 defines that a reader cannot infer from the message alone — the empty-string
 * reset, and the promise that a response never carries an empty currency.
 */
@QuarkusTest
class SettingsResourceTest {

  @BeforeEach
  void reset() {
    PrudentTest.reset();
  }

  @ParameterizedTest
  @ValueSource(strings = {PrudentTest.JSON, PrudentTest.PROTOBUF})
  @TestSecurity(user = PrudentTest.ALICE)
  void readThenWrite_roundTrips(String mode) throws Exception {
    Response read = PrudentTest.request(mode).when().get("/api/v1/settings").andReturn();
    assertEquals(200, read.statusCode());
    Settings settings = PrudentTest.decode(mode, read, Settings.newBuilder()).build();

    // A GET NEVER ANSWERS WITH AN EMPTY CURRENCY. proto3 has no presence for a string, so "" and
    // unset are the same bytes — the server resolves the default before answering rather than
    // leaving the client to guess which it received.
    assertFalse(settings.getMainCurrency().isBlank());
    assertEquals(SettingsEntity.DEFAULT_MAIN_CURRENCY, settings.getMainCurrency());

    Response written =
        PrudentTest.body(
                PrudentTest.request(mode),
                mode,
                UpdateSettingsRequest.newBuilder().setMainCurrency("eur").build())
            .when()
            .put("/api/v1/settings")
            .andReturn();
    assertEquals(200, written.statusCode());

    // THE RESPONSE CARRIES THE RESULT, not an empty body — the server may have substituted or
    // normalised, and a client that must re-read to learn what it wrote is a wasted round trip.
    // "eur" was sent; "EUR" comes back, because normalising is what stops one currency becoming two.
    assertEquals(
        "EUR", PrudentTest.decode(mode, written, Settings.newBuilder()).build().getMainCurrency());

    Response reread = PrudentTest.request(mode).when().get("/api/v1/settings").andReturn();
    assertEquals(
        "EUR", PrudentTest.decode(mode, reread, Settings.newBuilder()).build().getMainCurrency());
  }

  @ParameterizedTest
  @ValueSource(strings = {PrudentTest.JSON, PrudentTest.PROTOBUF})
  @TestSecurity(user = PrudentTest.ALICE)
  void anEmptyCurrency_resetsToTheDefault(String mode) throws Exception {
    PrudentTest.body(
            PrudentTest.request(mode),
            mode,
            UpdateSettingsRequest.newBuilder().setMainCurrency("USD").build())
        .when()
        .put("/api/v1/settings")
        .andReturn();

    // AN EMPTY VALUE MEANS "RESET TO THE DEFAULT", not "leave unchanged". That reading had to be
    // chosen because proto3 makes the two indistinguishable on the wire, and this asserts the one
    // ADR-009 chose — without it, neither side of the rule could be implemented.
    Response reset =
        PrudentTest.body(
                PrudentTest.request(mode),
                mode,
                UpdateSettingsRequest.newBuilder().setMainCurrency("").build())
            .when()
            .put("/api/v1/settings")
            .andReturn();

    assertEquals(200, reset.statusCode());
    assertEquals(
        SettingsEntity.DEFAULT_MAIN_CURRENCY,
        PrudentTest.decode(mode, reset, Settings.newBuilder()).build().getMainCurrency());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void anInvalidCurrency_isRejected() throws Exception {
    Response response =
        PrudentTest.body(
                PrudentTest.request(PrudentTest.JSON),
                PrudentTest.JSON,
                UpdateSettingsRequest.newBuilder().setMainCurrency("XYZ").build())
            .when()
            .put("/api/v1/settings")
            .andReturn();

    assertEquals(400, response.statusCode());
    ZenError error =
        PrudentTest.decode(PrudentTest.JSON, response, ZenError.newBuilder()).build();
    assertEquals("invalid", error.getCode());
    assertTrue(error.getMessage().contains("ISO-4217"));
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aCurrencyNoAccountHolds_isAccepted() throws Exception {
    // main_currency is a DISPLAY PREFERENCE, not a constraint on the user's accounts. A user who
    // picks a currency before opening their first account is a normal state, not an inconsistency
    // to reject — and Alice has no accounts at all here.
    Response response =
        PrudentTest.body(
                PrudentTest.request(PrudentTest.JSON),
                PrudentTest.JSON,
                UpdateSettingsRequest.newBuilder().setMainCurrency("JPY").build())
            .when()
            .put("/api/v1/settings")
            .andReturn();

    assertEquals(200, response.statusCode());
    assertEquals(
        "JPY",
        PrudentTest.decode(PrudentTest.JSON, response, Settings.newBuilder())
            .build()
            .getMainCurrency());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aWriteDoesNotReachTheOtherUsersSettings() throws Exception {
    // The singleton carries no id and the URL names none, so the ONLY thing separating Alice's
    // settings from Bob's is the token. Bob's row is seeded directly, because a test authenticated
    // as Alice cannot create one as Bob — which is the property being asserted.
    PrudentTest.seedSettings(PrudentTest.BOB, "JPY");

    PrudentTest.body(
            PrudentTest.request(PrudentTest.JSON),
            PrudentTest.JSON,
            UpdateSettingsRequest.newBuilder().setMainCurrency("USD").build())
        .when()
        .put("/api/v1/settings")
        .andReturn();

    Response mine = PrudentTest.request(PrudentTest.JSON).when().get("/api/v1/settings").andReturn();
    assertEquals(
        "USD",
        PrudentTest.decode(PrudentTest.JSON, mine, Settings.newBuilder()).build().getMainCurrency(),
        "the caller reads back their own write");

    assertEquals(
        "JPY",
        PrudentTest.storedCurrency(PrudentTest.BOB),
        "the other user's settings row must be untouched by a write made as this caller");
  }
}
