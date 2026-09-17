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
import prudent.proto.v1.Account;
import prudent.proto.v1.CreateTransferRequest;
import prudent.proto.v1.CurrencyBalance;
import prudent.proto.v1.ListAccountsResponse;
import prudent.proto.v1.Record;
import prudent.proto.v1.Transfer;
import prudent.proto.v1.UpdateRecordRequest;
import zen.proto.v1.ZenError;

/**
 * The transfer surface (jlogicsoftware/prudent#32): one operation that atomically links two
 * records, moves both accounts' derived balances, and is excluded from income/expense analytics —
 * plus the write-refusal that keeps {@code RecordResource} from breaking the pairing.
 */
@QuarkusTest
class TransferResourceTest {

  private UUID walletId;
  private UUID savingsId;

  @BeforeEach
  void reset() {
    PrudentTest.reset();
    walletId = PrudentTest.seedAccount(PrudentTest.ALICE, "Wallet", "PLN", "EUR");
    savingsId = PrudentTest.seedAccount(PrudentTest.ALICE, "Savings", "PLN");
  }

  private CreateTransferRequest.Builder validCreate() {
    return CreateTransferRequest.newBuilder()
        .setTitle("Move to savings")
        .setAmountMinor(50_00L)
        .setCurrency("PLN")
        .setDate("2026-08-17")
        .setFromAccountId(walletId.toString())
        .setToAccountId(savingsId.toString());
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
  void create_movesBothLegsAtomicallyAndUpdatesBothBalances(String mode) throws Exception {
    Response created =
        PrudentTest.body(PrudentTest.request(mode), mode, validCreate().build())
            .when()
            .post("/api/v1/transfers")
            .andReturn();
    assertEquals(201, created.statusCode());
    Transfer transfer = PrudentTest.decode(mode, created, Transfer.newBuilder()).build();

    assertFalse(transfer.getId().isBlank(), "the create response must carry a server-minted id");

    Record from = transfer.getFromRecord();
    Record to = transfer.getToRecord();
    assertEquals(-50_00L, from.getAmountMinor());
    assertEquals(50_00L, to.getAmountMinor());
    assertEquals("PLN", from.getCurrency());
    assertEquals("PLN", to.getCurrency());
    assertEquals(walletId.toString(), from.getAccountId());
    assertEquals(savingsId.toString(), to.getAccountId());
    assertEquals(transfer.getId(), from.getTransferId());
    assertEquals(transfer.getId(), to.getTransferId());
    assertFalse(from.hasCategoryId(), "a transfer leg carries no category");
    assertFalse(to.hasCategoryId(), "a transfer leg carries no category");

    // Reading each leg individually must agree — the linkage is stored, not synthesized.
    Response readFrom =
        PrudentTest.request(mode).when().get("/api/v1/records/" + from.getId()).andReturn();
    assertEquals(from, PrudentTest.decode(mode, readFrom, Record.newBuilder()).build());

    // Balances are DERIVED (ADR-014): persisting both legs in one transaction is the entire
    // "atomic balance update" — there is no Account row to update separately.
    assertEquals(-50_00L, balanceOf(mode, walletId, "PLN"));
    assertEquals(50_00L, balanceOf(mode, savingsId, "PLN"));
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void create_rejectsTheSameAccountOnBothSides() throws Exception {
    Response response =
        PrudentTest.body(
                PrudentTest.request(PrudentTest.JSON),
                PrudentTest.JSON,
                validCreate().setToAccountId(walletId.toString()).build())
            .when()
            .post("/api/v1/transfers")
            .andReturn();

    assertEquals(400, response.statusCode());
    assertEquals(
        "invalid",
        PrudentTest.decode(PrudentTest.JSON, response, ZenError.newBuilder()).build().getCode());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void create_rejectsANonPositiveAmount() throws Exception {
    Response response =
        PrudentTest.body(
                PrudentTest.request(PrudentTest.JSON),
                PrudentTest.JSON,
                validCreate().setAmountMinor(0L).build())
            .when()
            .post("/api/v1/transfers")
            .andReturn();

    assertEquals(400, response.statusCode());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void create_rejectsANegativeAmount() throws Exception {
    Response response =
        PrudentTest.body(
                PrudentTest.request(PrudentTest.JSON),
                PrudentTest.JSON,
                validCreate().setAmountMinor(-50_00L).build())
            .when()
            .post("/api/v1/transfers")
            .andReturn();

    assertEquals(400, response.statusCode());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void create_rejectsACurrencyAnAccountDoesNotHold() throws Exception {
    // savingsId only holds PLN.
    Response response =
        PrudentTest.body(
                PrudentTest.request(PrudentTest.JSON),
                PrudentTest.JSON,
                validCreate().setCurrency("EUR").build())
            .when()
            .post("/api/v1/transfers")
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
  void create_rejectsAnAccountThatIsNotTheCallers() throws Exception {
    UUID bobsAccount = PrudentTest.seedAccount(PrudentTest.BOB, "Bob's wallet", "PLN");

    Response response =
        PrudentTest.body(
                PrudentTest.request(PrudentTest.JSON),
                PrudentTest.JSON,
                validCreate().setToAccountId(bobsAccount.toString()).build())
            .when()
            .post("/api/v1/transfers")
            .andReturn();

    assertEquals(400, response.statusCode());
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
            .post("/api/v1/transfers")
            .andReturn();

    assertEquals(400, response.statusCode());
  }

  @ParameterizedTest
  @ValueSource(strings = {PrudentTest.JSON, PrudentTest.PROTOBUF})
  @TestSecurity(user = PrudentTest.ALICE)
  void delete_removesBothLegsAtomicallyAndRevertsBalances(String mode) throws Exception {
    Response created =
        PrudentTest.body(PrudentTest.request(mode), mode, validCreate().build())
            .when()
            .post("/api/v1/transfers")
            .andReturn();
    Transfer transfer = PrudentTest.decode(mode, created, Transfer.newBuilder()).build();

    Response deleted =
        PrudentTest.request(mode)
            .when()
            .delete("/api/v1/transfers/" + transfer.getId())
            .andReturn();
    assertEquals(204, deleted.statusCode());

    assertEquals(
        404,
        PrudentTest.request(mode)
            .when()
            .get("/api/v1/records/" + transfer.getFromRecord().getId())
            .andReturn()
            .statusCode());
    assertEquals(
        404,
        PrudentTest.request(mode)
            .when()
            .get("/api/v1/records/" + transfer.getToRecord().getId())
            .andReturn()
            .statusCode());

    assertEquals(0L, balanceOf(mode, walletId, "PLN"));
    assertEquals(0L, balanceOf(mode, savingsId, "PLN"));
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void delete_rejectsAnUnknownTransfer() throws Exception {
    Response response =
        PrudentTest.request(PrudentTest.JSON)
            .when()
            .delete("/api/v1/transfers/" + UUID.randomUUID())
            .andReturn();

    assertEquals(404, response.statusCode());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void delete_rejectsAnotherUsersTransfer() throws Exception {
    UUID bobsWallet = PrudentTest.seedAccount(PrudentTest.BOB, "Bob's wallet", "PLN");
    UUID bobsSavings = PrudentTest.seedAccount(PrudentTest.BOB, "Bob's savings", "PLN");
    UUID transferId = UUID.randomUUID();
    PrudentTest.seedTransferLeg(PrudentTest.BOB, bobsWallet, -10_00L, "PLN", transferId);
    PrudentTest.seedTransferLeg(PrudentTest.BOB, bobsSavings, 10_00L, "PLN", transferId);

    // Alice, authenticated, tries to delete Bob's transfer by its (guessed) id.
    Response response =
        PrudentTest.request(PrudentTest.JSON)
            .when()
            .delete("/api/v1/transfers/" + transferId)
            .andReturn();

    assertEquals(404, response.statusCode());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void recordResource_refusesToReplaceATransferLeg() throws Exception {
    Response created =
        PrudentTest.body(PrudentTest.request(PrudentTest.JSON), PrudentTest.JSON, validCreate().build())
            .when()
            .post("/api/v1/transfers")
            .andReturn();
    Transfer transfer = PrudentTest.decode(PrudentTest.JSON, created, Transfer.newBuilder()).build();
    Record leg = transfer.getFromRecord();

    UpdateRecordRequest update =
        UpdateRecordRequest.newBuilder()
            .setTitle("Tampered")
            .setAmountMinor(-1_00L)
            .setDate("2026-08-17")
            .setAccountId(leg.getAccountId())
            .setCurrency("PLN")
            .build();

    Response response =
        PrudentTest.body(PrudentTest.request(PrudentTest.JSON), PrudentTest.JSON, update)
            .when()
            .put("/api/v1/records/" + leg.getId())
            .andReturn();

    assertEquals(409, response.statusCode());
    assertEquals(
        "conflict",
        PrudentTest.decode(PrudentTest.JSON, response, ZenError.newBuilder()).build().getCode());

    // Unchanged: still reads exactly as the transfer created it.
    Response read =
        PrudentTest.request(PrudentTest.JSON).when().get("/api/v1/records/" + leg.getId()).andReturn();
    assertEquals(leg, PrudentTest.decode(PrudentTest.JSON, read, Record.newBuilder()).build());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void recordResource_refusesToDeleteATransferLeg() throws Exception {
    Response created =
        PrudentTest.body(PrudentTest.request(PrudentTest.JSON), PrudentTest.JSON, validCreate().build())
            .when()
            .post("/api/v1/transfers")
            .andReturn();
    Transfer transfer = PrudentTest.decode(PrudentTest.JSON, created, Transfer.newBuilder()).build();

    Response response =
        PrudentTest.request(PrudentTest.JSON)
            .when()
            .delete("/api/v1/records/" + transfer.getFromRecord().getId())
            .andReturn();

    assertEquals(409, response.statusCode());

    // Both legs are still present.
    assertEquals(
        200,
        PrudentTest.request(PrudentTest.JSON)
            .when()
            .get("/api/v1/records/" + transfer.getFromRecord().getId())
            .andReturn()
            .statusCode());
    assertEquals(
        200,
        PrudentTest.request(PrudentTest.JSON)
            .when()
            .get("/api/v1/records/" + transfer.getToRecord().getId())
            .andReturn()
            .statusCode());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void recordResource_stillAllowsReadingATransferLeg() throws Exception {
    Response created =
        PrudentTest.body(PrudentTest.request(PrudentTest.JSON), PrudentTest.JSON, validCreate().build())
            .when()
            .post("/api/v1/transfers")
            .andReturn();
    Transfer transfer = PrudentTest.decode(PrudentTest.JSON, created, Transfer.newBuilder()).build();

    assertEquals(
        200,
        PrudentTest.request(PrudentTest.JSON)
            .when()
            .get("/api/v1/records/" + transfer.getFromRecord().getId())
            .andReturn()
            .statusCode());

    Response listed = PrudentTest.request(PrudentTest.JSON).when().get("/api/v1/records").andReturn();
    assertEquals(200, listed.statusCode());
    assertTrue(listed.getBody().asString().contains(transfer.getFromRecord().getId()));

    assertNotEquals(
        transfer.getFromRecord().getId(),
        transfer.getToRecord().getId(),
        "sanity: the two legs must be distinct rows");
  }
}
