package prudent;

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
    assertFalse(record.hasPayee(), "a create request that omits payee must leave it absent");
    assertFalse(record.hasNote(), "a create request that omits note must leave it absent");

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
  void payeeAndNote_areOptionalAndSurviveTheRoundTrip(String mode) throws Exception {
    Response created =
        PrudentTest.body(
                PrudentTest.request(mode),
                mode,
                validCreate().setPayee("Corner Shop").setNote("Weekly groceries").build())
            .when()
            .post("/api/v1/records")
            .andReturn();
    assertEquals(201, created.statusCode());
    Record record = PrudentTest.decode(mode, created, Record.newBuilder()).build();
    assertEquals("Corner Shop", record.getPayee());
    assertEquals("Weekly groceries", record.getNote());

    Response read =
        PrudentTest.request(mode).when().get("/api/v1/records/" + record.getId()).andReturn();
    Record reread = PrudentTest.decode(mode, read, Record.newBuilder()).build();
    assertEquals("Corner Shop", reread.getPayee());
    assertEquals("Weekly groceries", reread.getNote());

    // A FULL REPLACEMENT that omits both fields clears them — same rule as every other field on
    // UpdateRecordRequest (records.proto).
    UpdateRecordRequest clearing =
        UpdateRecordRequest.newBuilder()
            .setTitle(record.getTitle())
            .setAmountMinor(record.getAmountMinor())
            .setDate(record.getDate())
            .setCategoryId(record.getCategoryId())
            .setAccountId(record.getAccountId())
            .setCurrency(record.getCurrency())
            .build();
    Response updated =
        PrudentTest.body(PrudentTest.request(mode), mode, clearing)
            .when()
            .put("/api/v1/records/" + record.getId())
            .andReturn();
    assertEquals(200, updated.statusCode());
    Record cleared = PrudentTest.decode(mode, updated, Record.newBuilder()).build();
    assertFalse(cleared.hasPayee(), "an update that omits payee must clear it, not keep the old value");
    assertFalse(cleared.hasNote(), "an update that omits note must clear it, not keep the old value");
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
  void zeroAmount_isRejected() throws Exception {
    // SIGNED (ADR-014): negative is an expense, positive is income, and zero moves nothing — a
    // record that does not change the balance is not a transaction.
    Response response =
        PrudentTest.body(
                PrudentTest.request(PrudentTest.JSON),
                PrudentTest.JSON,
                validCreate().setAmountMinor(0L).build())
            .when()
            .post("/api/v1/records")
            .andReturn();

    assertEquals(400, response.statusCode());
    assertEquals(
        "invalid",
        PrudentTest.decode(PrudentTest.JSON, response, ZenError.newBuilder()).build().getCode());
  }

  @ParameterizedTest
  @ValueSource(strings = {PrudentTest.JSON, PrudentTest.PROTOBUF})
  @TestSecurity(user = PrudentTest.ALICE)
  void aNegativeAmount_isAnExpenseAndSurvivesTheRoundTrip(String mode) throws Exception {
    Response created =
        PrudentTest.body(PrudentTest.request(mode), mode, validCreate().setAmountMinor(-5_00L).build())
            .when()
            .post("/api/v1/records")
            .andReturn();
    assertEquals(201, created.statusCode());
    assertEquals(
        -5_00L, PrudentTest.decode(mode, created, Record.newBuilder()).build().getAmountMinor());
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

  // --- Filters (jlogicsoftware/prudent#52) ---------------------------------------------------

  private ListRecordsResponse list(String... queryParamPairs) throws Exception {
    var spec = PrudentTest.request(PrudentTest.JSON);
    for (int i = 0; i < queryParamPairs.length; i += 2) {
      spec = spec.queryParam(queryParamPairs[i], queryParamPairs[i + 1]);
    }
    Response response = spec.when().get("/api/v1/records").andReturn();
    assertEquals(200, response.statusCode());
    return PrudentTest.decode(PrudentTest.JSON, response, ListRecordsResponse.newBuilder())
        .build();
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void noFilters_returnsTheFullUnfilteredList() throws Exception {
    PrudentTest.seedRecord(PrudentTest.ALICE, accountId, categoryId, -5_00L, "PLN");
    PrudentTest.seedRecord(PrudentTest.ALICE, accountId, categoryId, 10_00L, "PLN");

    assertEquals(2, list().getRecordsCount());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void dateRange_isInclusiveOnBothEnds() throws Exception {
    PrudentTest.seedRecord(
        PrudentTest.ALICE, accountId, categoryId, -1_00L, "PLN", java.time.LocalDate.of(2026, 8, 1));
    PrudentTest.seedRecord(
        PrudentTest.ALICE, accountId, categoryId, -2_00L, "PLN", java.time.LocalDate.of(2026, 8, 15));
    PrudentTest.seedRecord(
        PrudentTest.ALICE, accountId, categoryId, -3_00L, "PLN", java.time.LocalDate.of(2026, 8, 31));

    ListRecordsResponse inRange = list("dateFrom", "2026-08-01", "dateTo", "2026-08-15");
    assertEquals(2, inRange.getRecordsCount());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void accountFilter_matchesOnlyThatAccount() throws Exception {
    UUID otherAccount = PrudentTest.seedAccount(PrudentTest.ALICE, "Savings", "PLN");
    PrudentTest.seedRecord(PrudentTest.ALICE, accountId, categoryId, -1_00L, "PLN");
    PrudentTest.seedRecord(PrudentTest.ALICE, otherAccount, categoryId, -2_00L, "PLN");

    ListRecordsResponse filtered = list("accountId", accountId.toString());
    assertEquals(1, filtered.getRecordsCount());
    assertEquals(accountId.toString(), filtered.getRecords(0).getAccountId());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void categoryFilter_matchesOnlyThatCategory() throws Exception {
    UUID otherCategory = PrudentTest.seedCategory(PrudentTest.ALICE, "Transport");
    PrudentTest.seedRecord(PrudentTest.ALICE, accountId, categoryId, -1_00L, "PLN");
    PrudentTest.seedRecord(PrudentTest.ALICE, accountId, otherCategory, -2_00L, "PLN");

    ListRecordsResponse filtered = list("categoryId", categoryId.toString());
    assertEquals(1, filtered.getRecordsCount());
    assertEquals(categoryId.toString(), filtered.getRecords(0).getCategoryId());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void typeFilter_splitsIncomeExpenseAndTransfer() throws Exception {
    PrudentTest.seedRecord(PrudentTest.ALICE, accountId, categoryId, -5_00L, "PLN"); // expense
    PrudentTest.seedRecord(PrudentTest.ALICE, accountId, categoryId, 7_00L, "PLN"); // income
    UUID transferId = UUID.randomUUID();
    PrudentTest.seedTransferLeg(PrudentTest.ALICE, accountId, -3_00L, "PLN", transferId);

    assertEquals(1, list("type", "expense").getRecordsCount());
    assertEquals(1, list("type", "income").getRecordsCount());
    assertEquals(1, list("type", "transfer").getRecordsCount());
    assertEquals(3, list().getRecordsCount());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void amountRange_matchesTheAbsoluteAmountRegardlessOfSign() throws Exception {
    PrudentTest.seedRecord(PrudentTest.ALICE, accountId, categoryId, -50_00L, "PLN");
    PrudentTest.seedRecord(PrudentTest.ALICE, accountId, categoryId, 100_00L, "PLN");
    PrudentTest.seedRecord(PrudentTest.ALICE, accountId, categoryId, -500_00L, "PLN");

    ListRecordsResponse filtered = list("amountMin", "4000", "amountMax", "15000");
    assertEquals(2, filtered.getRecordsCount());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void search_matchesTitlePayeeOrNote() throws Exception {
    PrudentTest.body(PrudentTest.request(PrudentTest.JSON), PrudentTest.JSON, validCreate().setTitle("Groceries").build())
        .when().post("/api/v1/records").andReturn();
    PrudentTest.body(
            PrudentTest.request(PrudentTest.JSON),
            PrudentTest.JSON,
            validCreate().setTitle("Coffee").setPayee("Corner Shop").build())
        .when().post("/api/v1/records").andReturn();
    PrudentTest.body(
            PrudentTest.request(PrudentTest.JSON),
            PrudentTest.JSON,
            validCreate().setTitle("Lunch").setNote("with the corner-shop owner").build())
        .when().post("/api/v1/records").andReturn();

    assertEquals(2, list("search", "corner").getRecordsCount());
    assertEquals(1, list("search", "Groceries").getRecordsCount());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void filtersCompose_asAnAndAcrossAllGivenCriteria() throws Exception {
    UUID otherAccount = PrudentTest.seedAccount(PrudentTest.ALICE, "Savings", "PLN");
    PrudentTest.seedRecord(PrudentTest.ALICE, accountId, categoryId, -5_00L, "PLN"); // matches
    PrudentTest.seedRecord(PrudentTest.ALICE, accountId, categoryId, 5_00L, "PLN"); // wrong type
    PrudentTest.seedRecord(PrudentTest.ALICE, otherAccount, categoryId, -5_00L, "PLN"); // wrong account

    ListRecordsResponse filtered =
        list("accountId", accountId.toString(), "categoryId", categoryId.toString(), "type", "expense");
    assertEquals(1, filtered.getRecordsCount());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void clearingFilters_returnsToTheFullListWithNoDataLost() throws Exception {
    PrudentTest.seedRecord(PrudentTest.ALICE, accountId, categoryId, -5_00L, "PLN");
    PrudentTest.seedRecord(PrudentTest.ALICE, accountId, categoryId, 10_00L, "PLN");

    assertEquals(1, list("type", "expense").getRecordsCount());
    assertEquals(2, list().getRecordsCount(), "clearing the filter must restore every record");
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aMalformedDateFilter_isRejected() throws Exception {
    Response response =
        PrudentTest.request(PrudentTest.JSON)
            .queryParam("dateFrom", "not-a-date")
            .when()
            .get("/api/v1/records")
            .andReturn();
    assertEquals(400, response.statusCode());
    assertEquals(
        "invalid",
        PrudentTest.decode(PrudentTest.JSON, response, ZenError.newBuilder()).build().getCode());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aMalformedAccountIdFilter_isRejected() throws Exception {
    Response response =
        PrudentTest.request(PrudentTest.JSON)
            .queryParam("accountId", "not-a-uuid")
            .when()
            .get("/api/v1/records")
            .andReturn();
    assertEquals(400, response.statusCode());
    assertEquals(
        "invalid",
        PrudentTest.decode(PrudentTest.JSON, response, ZenError.newBuilder()).build().getCode());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void anInvalidTypeFilter_isRejected() throws Exception {
    Response response =
        PrudentTest.request(PrudentTest.JSON)
            .queryParam("type", "bogus")
            .when()
            .get("/api/v1/records")
            .andReturn();
    assertEquals(400, response.statusCode());
    assertEquals(
        "invalid",
        PrudentTest.decode(PrudentTest.JSON, response, ZenError.newBuilder()).build().getCode());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aNegativeAmountMin_isRejected() throws Exception {
    Response response =
        PrudentTest.request(PrudentTest.JSON)
            .queryParam("amountMin", -1)
            .when()
            .get("/api/v1/records")
            .andReturn();
    assertEquals(400, response.statusCode());
    assertEquals(
        "invalid",
        PrudentTest.decode(PrudentTest.JSON, response, ZenError.newBuilder()).build().getCode());
  }
}
