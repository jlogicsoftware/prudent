package prudent.server;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.security.TestSecurity;
import io.restassured.response.Response;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import prudent.proto.v1.CreateRecordRequest;
import prudent.proto.v1.ListRecordsResponse;
import prudent.proto.v1.Record;
import prudent.proto.v1.UpdateRecordRequest;
import zen.proto.v1.ZenError;

/**
 * The record surface: CRUD in both transport modes, the money guarantee, and the refusals that
 * replaced currency inheritance when an account gained several currencies.
 */
@QuarkusTest
class RecordResourceTest {

  private UUID accountId;
  private UUID categoryId;

  @BeforeEach
  void reset() {
    PrudentTest.reset();
    accountId = PrudentTest.seedAccount(PrudentTest.ALICE, "Wallet", "PLN", "EUR");
    categoryId = PrudentTest.seedCategory(PrudentTest.ALICE, "Food");
  }

  private CreateRecordRequest.Builder validCreate() {
    return CreateRecordRequest.newBuilder()
        .setTitle("Coffee")
        .setAmountMinor(12_50L)
        .setDate("2026-08-17")
        .setCategoryId(categoryId.toString())
        .setAccountId(accountId.toString())
        .setCurrency("PLN");
  }

  @ParameterizedTest
  @ValueSource(strings = {PrudentTest.JSON, PrudentTest.PROTOBUF})
  @TestSecurity(user = PrudentTest.ALICE)
  void crud_roundTrips(String mode) throws Exception {
    Response created =
        PrudentTest.body(PrudentTest.request(mode), mode, validCreate().build())
            .when()
            .post("/api/v1/records")
            .andReturn();
    assertEquals(201, created.statusCode());
    Record record = PrudentTest.decode(mode, created, Record.newBuilder()).build();

    assertFalse(record.getId().isBlank(), "the create response must carry a server-minted id");
    assertEquals("Coffee", record.getTitle());
    assertEquals(12_50L, record.getAmountMinor());
    assertEquals("PLN", record.getCurrency());
    assertEquals("2026-08-17", record.getDate());
    assertEquals(accountId.toString(), record.getAccountId());

    Response read =
        PrudentTest.request(mode).when().get("/api/v1/records/" + record.getId()).andReturn();
    assertEquals(record, PrudentTest.decode(mode, read, Record.newBuilder()).build());

    Response listed = PrudentTest.request(mode).when().get("/api/v1/records").andReturn();
    ListRecordsResponse list =
        PrudentTest.decode(mode, listed, ListRecordsResponse.newBuilder()).build();
    assertEquals(1, list.getRecordsCount());

    UpdateRecordRequest update =
        UpdateRecordRequest.newBuilder()
            .setTitle("Coffee and cake")
            .setAmountMinor(21_00L)
            .setDate("2026-08-18")
            .setCategoryId(categoryId.toString())
            .setAccountId(accountId.toString())
            .setCurrency("EUR")
            .build();
    Response updated =
        PrudentTest.body(PrudentTest.request(mode), mode, update)
            .when()
            .put("/api/v1/records/" + record.getId())
            .andReturn();
    assertEquals(200, updated.statusCode());
    Record replaced = PrudentTest.decode(mode, updated, Record.newBuilder()).build();
    assertEquals(record.getId(), replaced.getId(), "an update must not re-mint the id");
    assertEquals("EUR", replaced.getCurrency());
    assertEquals(21_00L, replaced.getAmountMinor());

    Response deleted =
        PrudentTest.request(mode).when().delete("/api/v1/records/" + record.getId()).andReturn();
    assertEquals(204, deleted.statusCode());
    assertEquals(
        404,
        PrudentTest.request(mode)
            .when()
            .get("/api/v1/records/" + record.getId())
            .andReturn()
            .statusCode());
  }

  @ParameterizedTest
  @ValueSource(strings = {PrudentTest.JSON, PrudentTest.PROTOBUF})
  @TestSecurity(user = PrudentTest.ALICE)
  void money_survivesTheRoundTripExactly(String mode) throws Exception {
    // 0.10 + 0.20 in binary floating point is 0.30000000000000004. As minor units it is 10 + 20 =
    // 30, exactly, which is the entire reason the contract carries an int64 rather than a double.
    // The value below is also beyond a double's exact-integer range (2^53), so a stack that widened
    // it to a double anywhere along the path would return a DIFFERENT number rather than an error.
    long unrepresentableAsDouble = 9_007_199_254_740_993L; // 2^53 + 1

    Response created =
        PrudentTest.body(
                PrudentTest.request(mode),
                mode,
                validCreate().setAmountMinor(unrepresentableAsDouble).build())
            .when()
            .post("/api/v1/records")
            .andReturn();
    assertEquals(201, created.statusCode());
    Record record = PrudentTest.decode(mode, created, Record.newBuilder()).build();
    assertEquals(unrepresentableAsDouble, record.getAmountMinor());

    // And again after a full database round trip, because the column is what a later read returns.
    Response read =
        PrudentTest.request(mode).when().get("/api/v1/records/" + record.getId()).andReturn();
    assertEquals(
        unrepresentableAsDouble,
        PrudentTest.decode(mode, read, Record.newBuilder()).build().getAmountMinor());

    assertNotEquals(
        (long) (double) unrepresentableAsDouble,
        unrepresentableAsDouble,
        "sanity: this value must genuinely be unrepresentable as a double, or the test proves"
            + " nothing");
  }

  @ParameterizedTest
  @ValueSource(strings = {PrudentTest.JSON, PrudentTest.PROTOBUF})
  @TestSecurity(user = PrudentTest.ALICE)
  void aCurrencyTheAccountDoesNotHold_isRejected(String mode) throws Exception {
    // THE REFUSAL THAT REPLACED INHERITANCE (ADR-008). The account holds PLN and EUR; USD is a real
    // ISO-4217 currency and is still refused, because this account does not hold it.
    Response response =
        PrudentTest.body(PrudentTest.request(mode), mode, validCreate().setCurrency("USD").build())
            .when()
            .post("/api/v1/records")
            .andReturn();

    assertEquals(400, response.statusCode());
    ZenError error = PrudentTest.decode(mode, response, ZenError.newBuilder()).build();
    assertEquals("invalid", error.getCode());
    assertTrue(error.getMessage().contains("USD"));
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void movingToAnAccountThatDoesNotHoldTheCurrency_isRejected() throws Exception {
    // Moving a record between accounts and changing its currency are ONE operation, validated
    // together — checking the currency against the OLD account would let this through.
    UUID plnOnly = PrudentTest.seedAccount(PrudentTest.ALICE, "PLN only", "PLN");
    UUID recordId = PrudentTest.seedRecord(PrudentTest.ALICE, accountId, categoryId, 30_00L, "EUR");

    UpdateRecordRequest move =
        UpdateRecordRequest.newBuilder()
            .setTitle("Moved")
            .setAmountMinor(30_00L)
            .setDate("2026-08-17")
            .setCategoryId(categoryId.toString())
            .setAccountId(plnOnly.toString())
            .setCurrency("EUR")
            .build();

    Response response =
        PrudentTest.body(PrudentTest.request(PrudentTest.JSON), PrudentTest.JSON, move)
            .when()
            .put("/api/v1/records/" + recordId)
            .andReturn();

    assertEquals(400, response.statusCode());
    assertTrue(
        PrudentTest.decode(PrudentTest.JSON, response, ZenError.newBuilder())
            .build()
            .getMessage()
            .contains("EUR"));
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void invalidCurrency_isRejected() throws Exception {
    Response response =
        PrudentTest.body(
                PrudentTest.request(PrudentTest.JSON),
                PrudentTest.JSON,
                validCreate().setCurrency("XYZ").build())
            .when()
            .post("/api/v1/records")
            .andReturn();

    assertEquals(400, response.statusCode());
    assertTrue(
        PrudentTest.decode(PrudentTest.JSON, response, ZenError.newBuilder())
            .build()
            .getMessage()
            .contains("ISO-4217"));
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aMalformedDate_isRejectedRatherThanDefaulted() throws Exception {
    // 2026-02-30 does not exist. LocalDate.parse refuses it rather than rolling it into March,
    // which is the behaviour wanted: a rolled date files a record in a month the user did not
    // choose, and that is a wrong total in two months at once.
    Response response =
        PrudentTest.body(
                PrudentTest.request(PrudentTest.JSON),
                PrudentTest.JSON,
                validCreate().setDate("2026-02-30").build())
            .when()
            .post("/api/v1/records")
            .andReturn();

    assertEquals(400, response.statusCode());
    assertEquals(
        "invalid",
        PrudentTest.decode(PrudentTest.JSON, response, ZenError.newBuilder()).build().getCode());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void anAccountThatIsNotTheCallers_isRejected() throws Exception {
    UUID bobsAccount = PrudentTest.seedAccount(PrudentTest.BOB, "Bob's wallet", "PLN");

    Response response =
        PrudentTest.body(
                PrudentTest.request(PrudentTest.JSON),
                PrudentTest.JSON,
                validCreate().setAccountId(bobsAccount.toString()).build())
            .when()
            .post("/api/v1/records")
            .andReturn();

    assertEquals(400, response.statusCode());
  }
}
