package prudent;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.security.TestSecurity;
import io.restassured.response.Response;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import prudent.proto.v1.Account;
import prudent.proto.v1.CreateCorrectionRequest;
import prudent.proto.v1.CurrencyBalance;
import prudent.proto.v1.ListAccountsResponse;
import prudent.proto.v1.ListRecordsResponse;
import prudent.proto.v1.Record;
import prudent.proto.v1.UpdateRecordRequest;
import zen.proto.v1.ZenError;

/**
 * The balance-correction surface (M1, jlogicsoftware/prudent#53): an explicit, auditable way to
 * reconcile an account's derived balance against a real-world figure, without rewriting the
 * opening balance or any existing record — plus the write-refusal that keeps {@code
 * RecordResource} from letting a correction be edited away.
 */
@QuarkusTest
class CorrectionResourceTest {

  private UUID walletId;

  @BeforeEach
  void reset() {
    PrudentTest.reset();
    walletId = PrudentTest.seedAccount(PrudentTest.ALICE, "Wallet", "PLN", "EUR");
  }

  private CreateCorrectionRequest.Builder validCreate() {
    return CreateCorrectionRequest.newBuilder()
        .setAccountId(walletId.toString())
        .setCurrency("PLN")
        .setBalanceMinor(100_00L)
        .setDate("2026-08-17");
  }

  private long balanceOf(String mode, UUID accountId, String currency) throws Exception {
    Response listed = PrudentTest.request(mode).when().get("/api/v1/accounts").andReturn();
    ListAccountsResponse accounts =
        PrudentTest.decode(mode, listed, ListAccountsResponse.newBuilder()).build();
    for (Account account : accounts.getAccountsList()) {
      if (account.getId().equals(accountId.toString())) {
        for (CurrencyBalance balance : account.getBalancesList()) {
          if (balance.getCurrency().equals(currency)) {
            return balance.getAmountMinor();
          }
        }
      }
    }
    return 0L;
  }

  @ParameterizedTest
  @ValueSource(strings = {PrudentTest.JSON, PrudentTest.PROTOBUF})
  @TestSecurity(user = PrudentTest.ALICE)
  void create_recordsTheDeltaAndUpdatesTheDerivedBalance(String mode) throws Exception {
    // Starting balance is 0 (seeded with no records); asking for 100.00 PLN needs a +100.00 delta.
    Response created =
        PrudentTest.body(PrudentTest.request(mode), mode, validCreate().build())
            .when()
            .post("/api/v1/corrections")
            .andReturn();
    assertEquals(201, created.statusCode());
    Record record = PrudentTest.decode(mode, created, Record.newBuilder()).build();

    assertFalse(record.getId().isBlank(), "the create response must carry a server-minted id");
    assertEquals(100_00L, record.getAmountMinor());
    assertEquals("PLN", record.getCurrency());
    assertEquals(walletId.toString(), record.getAccountId());
    assertTrue(record.getIsCorrection());
    assertFalse(record.hasCategoryId(), "a correction carries no category");
    assertEquals("Balance correction", record.getTitle());

    assertEquals(100_00L, balanceOf(mode, walletId, "PLN"));

    // Reading it back individually must agree — the correction is a stored row, not synthesized.
    Response read =
        PrudentTest.request(mode).when().get("/api/v1/records/" + record.getId()).andReturn();
    assertEquals(record, PrudentTest.decode(mode, read, Record.newBuilder()).build());
  }

  @ParameterizedTest
  @ValueSource(strings = {PrudentTest.JSON, PrudentTest.PROTOBUF})
  @TestSecurity(user = PrudentTest.ALICE)
  void create_computesANegativeDeltaWhenTheRealBalanceIsLower(String mode) throws Exception {
    UUID categoryId = PrudentTest.seedCategory(PrudentTest.ALICE, "Groceries");
    PrudentTest.seedRecord(PrudentTest.ALICE, walletId, categoryId, 150_00L, "PLN");

    Response created =
        PrudentTest.body(
                PrudentTest.request(mode), mode, validCreate().setBalanceMinor(100_00L).build())
            .when()
            .post("/api/v1/corrections")
            .andReturn();
    assertEquals(201, created.statusCode());
    Record record = PrudentTest.decode(mode, created, Record.newBuilder()).build();

    // Derived balance was 150.00; the caller says the true balance is 100.00, so the correction
    // must be a NEGATIVE 50.00 delta.
    assertEquals(-50_00L, record.getAmountMinor());
    assertEquals(100_00L, balanceOf(mode, walletId, "PLN"));
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void create_optionalTitleAndNoteAreStoredWhenGiven() throws Exception {
    Response created =
        PrudentTest.body(
                PrudentTest.request(PrudentTest.JSON),
                PrudentTest.JSON,
                validCreate().setTitle("Reconciled with bank").setNote("Statement dated 2026-08-16").build())
            .when()
            .post("/api/v1/corrections")
            .andReturn();
    assertEquals(201, created.statusCode());
    Record record = PrudentTest.decode(PrudentTest.JSON, created, Record.newBuilder()).build();

    assertEquals("Reconciled with bank", record.getTitle());
    assertEquals("Statement dated 2026-08-16", record.getNote());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void create_rejectsATargetThatAlreadyMatchesTheCurrentBalance() throws Exception {
    // Starting balance is 0; asking to "correct" to 0 changes nothing.
    Response response =
        PrudentTest.body(
                PrudentTest.request(PrudentTest.JSON),
                PrudentTest.JSON,
                validCreate().setBalanceMinor(0L).build())
            .when()
            .post("/api/v1/corrections")
            .andReturn();

    assertEquals(400, response.statusCode());
    assertEquals(
        "invalid",
        PrudentTest.decode(PrudentTest.JSON, response, ZenError.newBuilder()).build().getCode());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void create_rejectsAnAccountThatIsNotTheCallers() throws Exception {
    UUID bobsAccount = PrudentTest.seedAccount(PrudentTest.BOB, "Bob's wallet", "PLN");

    Response response =
        PrudentTest.body(
                PrudentTest.request(PrudentTest.JSON),
                PrudentTest.JSON,
                validCreate().setAccountId(bobsAccount.toString()).build())
            .when()
            .post("/api/v1/corrections")
            .andReturn();

    assertEquals(400, response.statusCode());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void create_rejectsACurrencyTheAccountDoesNotHold() throws Exception {
    // walletId holds PLN and EUR, but not USD.
    Response response =
        PrudentTest.body(
                PrudentTest.request(PrudentTest.JSON),
                PrudentTest.JSON,
                validCreate().setCurrency("USD").build())
            .when()
            .post("/api/v1/corrections")
            .andReturn();

    assertEquals(400, response.statusCode());
    assertTrue(
        PrudentTest.decode(PrudentTest.JSON, response, ZenError.newBuilder())
            .build()
            .getMessage()
            .contains("USD"));
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void create_rejectsAMalformedDate() throws Exception {
    Response response =
        PrudentTest.body(
                PrudentTest.request(PrudentTest.JSON),
                PrudentTest.JSON,
                validCreate().setDate("2026-02-30").build())
            .when()
            .post("/api/v1/corrections")
            .andReturn();

    assertEquals(400, response.statusCode());
  }

  @ParameterizedTest
  @ValueSource(strings = {PrudentTest.JSON, PrudentTest.PROTOBUF})
  @TestSecurity(user = PrudentTest.ALICE)
  void delete_removesTheCorrectionAndRevertsTheBalance(String mode) throws Exception {
    Response created =
        PrudentTest.body(PrudentTest.request(mode), mode, validCreate().build())
            .when()
            .post("/api/v1/corrections")
            .andReturn();
    Record record = PrudentTest.decode(mode, created, Record.newBuilder()).build();

    Response deleted =
        PrudentTest.request(mode).when().delete("/api/v1/corrections/" + record.getId()).andReturn();
    assertEquals(204, deleted.statusCode());

    assertEquals(
        404,
        PrudentTest.request(mode)
            .when()
            .get("/api/v1/records/" + record.getId())
            .andReturn()
            .statusCode());
    assertEquals(0L, balanceOf(mode, walletId, "PLN"));
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void delete_rejectsAnUnknownCorrection() throws Exception {
    Response response =
        PrudentTest.request(PrudentTest.JSON)
            .when()
            .delete("/api/v1/corrections/" + UUID.randomUUID())
            .andReturn();

    assertEquals(404, response.statusCode());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void delete_rejectsAnOrdinaryRecordIdEvenThoughItIsTheCallersOwn() throws Exception {
    UUID categoryId = PrudentTest.seedCategory(PrudentTest.ALICE, "Groceries");
    UUID recordId = PrudentTest.seedRecord(PrudentTest.ALICE, walletId, categoryId, -10_00L, "PLN");

    Response response =
        PrudentTest.request(PrudentTest.JSON)
            .when()
            .delete("/api/v1/corrections/" + recordId)
            .andReturn();

    // The id is real and owned by the caller, but it is not a correction — this endpoint is not
    // the general record-delete path.
    assertEquals(404, response.statusCode());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void recordResource_refusesToReplaceACorrection() throws Exception {
    Response created =
        PrudentTest.body(PrudentTest.request(PrudentTest.JSON), PrudentTest.JSON, validCreate().build())
            .when()
            .post("/api/v1/corrections")
            .andReturn();
    Record correction = PrudentTest.decode(PrudentTest.JSON, created, Record.newBuilder()).build();

    UpdateRecordRequest update =
        UpdateRecordRequest.newBuilder()
            .setTitle("Tampered")
            .setAmountMinor(-1_00L)
            .setDate("2026-08-17")
            .setAccountId(correction.getAccountId())
            .setCurrency("PLN")
            .build();

    Response response =
        PrudentTest.body(PrudentTest.request(PrudentTest.JSON), PrudentTest.JSON, update)
            .when()
            .put("/api/v1/records/" + correction.getId())
            .andReturn();

    assertEquals(409, response.statusCode());
    assertEquals(
        "conflict",
        PrudentTest.decode(PrudentTest.JSON, response, ZenError.newBuilder()).build().getCode());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void recordResource_refusesToDeleteACorrection() throws Exception {
    Response created =
        PrudentTest.body(PrudentTest.request(PrudentTest.JSON), PrudentTest.JSON, validCreate().build())
            .when()
            .post("/api/v1/corrections")
            .andReturn();
    Record correction = PrudentTest.decode(PrudentTest.JSON, created, Record.newBuilder()).build();

    Response response =
        PrudentTest.request(PrudentTest.JSON)
            .when()
            .delete("/api/v1/records/" + correction.getId())
            .andReturn();

    assertEquals(409, response.statusCode());
    assertEquals(
        200,
        PrudentTest.request(PrudentTest.JSON)
            .when()
            .get("/api/v1/records/" + correction.getId())
            .andReturn()
            .statusCode());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void recordResource_listSupportsTheCorrectionTypeFilter() throws Exception {
    UUID categoryId = PrudentTest.seedCategory(PrudentTest.ALICE, "Groceries");
    PrudentTest.seedRecord(PrudentTest.ALICE, walletId, categoryId, -10_00L, "PLN");
    Response created =
        PrudentTest.body(PrudentTest.request(PrudentTest.JSON), PrudentTest.JSON, validCreate().build())
            .when()
            .post("/api/v1/corrections")
            .andReturn();
    Record correction = PrudentTest.decode(PrudentTest.JSON, created, Record.newBuilder()).build();

    Response listed =
        PrudentTest.request(PrudentTest.JSON)
            .when()
            .get("/api/v1/records?type=correction")
            .andReturn();
    assertEquals(200, listed.statusCode());
    ListRecordsResponse response =
        PrudentTest.decode(PrudentTest.JSON, listed, ListRecordsResponse.newBuilder()).build();
    assertEquals(1, response.getRecordsCount(), "only the correction should match type=correction");
    assertEquals(correction.getId(), response.getRecords(0).getId());
    assertTrue(response.getRecords(0).getIsCorrection());
  }
}
