package prudent;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.quarkus.narayana.jta.QuarkusTransaction;
import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.security.TestSecurity;
import io.restassured.response.Response;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import prudent.proto.v1.AccountType;
import prudent.proto.v1.CreateAccountRequest;
import prudent.proto.v1.CreateRecordRequest;
import prudent.proto.v1.CurrencyBalance;
import prudent.proto.v1.ListAccountsResponse;
import prudent.proto.v1.ListCategoriesResponse;
import prudent.proto.v1.ListRecordsResponse;
import prudent.proto.v1.UpdateAccountRequest;
import prudent.proto.v1.UpdateCategoryRequest;
import prudent.proto.v1.UpdateRecordRequest;
import prudent.account.AccountEntity;
import prudent.category.CategoryEntity;
import prudent.record.RecordEntity;
import zen.proto.v1.ZenError;

/**
 * <strong>The suite that would catch the worst defect this phase can ship.</strong>
 *
 * <p>Every row Prudent holds is one user's money. A server that resolved ownership from the request
 * instead of the token would serve every request successfully and simply serve the wrong person's
 * data — no error, no log line, and every single-user test still green. That failure is invisible
 * from inside one identity, so the only thing that catches it is two.
 *
 * <p><strong>Every verb, not once.</strong> Read, list, update and delete are four separate lookups
 * in four separate methods, and a scoping filter present in three of them is a scoping filter that
 * leaks through the fourth. They are asserted individually for that reason.
 *
 * <p><strong>404, not 403, and that is deliberate.</strong> Answering "forbidden" for a row that
 * exists but belongs to someone else confirms the row exists to someone who cannot see it, turning
 * any id into an existence oracle. The caller learns only that <em>they</em> have no such row.
 */
@QuarkusTest
class UserScopingTest {

  private UUID bobsAccount;
  private UUID bobsCategory;
  private UUID bobsRecord;

  @BeforeEach
  void seedBobsData() {
    PrudentTest.reset();
    bobsAccount = PrudentTest.seedAccount(PrudentTest.BOB, "Bob's wallet", "PLN");
    bobsCategory = PrudentTest.seedCategory(PrudentTest.BOB, "Bob's groceries");
    bobsRecord = PrudentTest.seedRecord(PrudentTest.BOB, bobsAccount, bobsCategory, 99_00L, "PLN");
  }

  // -----------------------------------------------------------------------------------------
  // Accounts
  // -----------------------------------------------------------------------------------------

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void account_read_isNotFound() {
    assertEquals(404, get("/api/v1/accounts/" + bobsAccount).statusCode());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void account_list_omitsTheOtherUsersRows() throws Exception {
    Response response = get("/api/v1/accounts");
    assertEquals(200, response.statusCode());
    ListAccountsResponse list =
        PrudentTest.decode(PrudentTest.JSON, response, ListAccountsResponse.newBuilder()).build();
    assertEquals(0, list.getAccountsCount(), "Alice owns no accounts and must see none of Bob's");
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void account_update_isNotFoundAndChangesNothing() throws Exception {
    UpdateAccountRequest hijack =
        UpdateAccountRequest.newBuilder()
            .setName("Taken over")
            .setType(AccountType.ACCOUNT_TYPE_CASH)
            .addBalances(CurrencyBalance.newBuilder().setCurrency("PLN").setAmountMinor(0L))
            .build();

    Response response =
        PrudentTest.body(PrudentTest.request(PrudentTest.JSON), PrudentTest.JSON, hijack)
            .when()
            .put("/api/v1/accounts/" + bobsAccount)
            .andReturn();

    assertEquals(404, response.statusCode());
    assertNotFoundBody(response);
    // The refusal is asserted at the row as well as at the status: a handler that answered 404
    // AFTER writing would be a worse defect than one that answered 200.
    assertEquals(
        "Bob's wallet",
        QuarkusTransaction.requiringNew()
            .call(() -> AccountEntity.<AccountEntity>findById(bobsAccount).name));
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void account_delete_isNotFoundAndDeletesNothing() {
    Response response =
        PrudentTest.request(PrudentTest.JSON)
            .when()
            .delete("/api/v1/accounts/" + bobsAccount)
            .andReturn();

    assertEquals(404, response.statusCode());
    assertTrue(
        QuarkusTransaction.requiringNew().call(() -> AccountEntity.findById(bobsAccount) != null),
        "the other user's account must still exist");
  }

  // -----------------------------------------------------------------------------------------
  // Categories
  // -----------------------------------------------------------------------------------------

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void category_read_isNotFound() {
    assertEquals(404, get("/api/v1/categories/" + bobsCategory).statusCode());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void category_list_omitsTheOtherUsersRows() throws Exception {
    Response response = get("/api/v1/categories");
    ListCategoriesResponse list =
        PrudentTest.decode(PrudentTest.JSON, response, ListCategoriesResponse.newBuilder()).build();
    assertEquals(0, list.getCategoriesCount());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void category_update_isNotFoundAndChangesNothing() throws Exception {
    UpdateCategoryRequest hijack =
        UpdateCategoryRequest.newBuilder().setTitle("Taken over").setIconKey("work").build();

    Response response =
        PrudentTest.body(PrudentTest.request(PrudentTest.JSON), PrudentTest.JSON, hijack)
            .when()
            .put("/api/v1/categories/" + bobsCategory)
            .andReturn();

    assertEquals(404, response.statusCode());
    assertEquals(
        "Bob's groceries",
        QuarkusTransaction.requiringNew()
            .call(() -> CategoryEntity.<CategoryEntity>findById(bobsCategory).title));
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void category_delete_isNotFoundAndDeletesNothing() {
    assertEquals(
        404,
        PrudentTest.request(PrudentTest.JSON)
            .when()
            .delete("/api/v1/categories/" + bobsCategory)
            .andReturn()
            .statusCode());
    assertTrue(
        QuarkusTransaction.requiringNew().call(() -> CategoryEntity.findById(bobsCategory) != null));
  }

  // -----------------------------------------------------------------------------------------
  // Records
  // -----------------------------------------------------------------------------------------

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void record_read_isNotFound() {
    assertEquals(404, get("/api/v1/records/" + bobsRecord).statusCode());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void record_list_omitsTheOtherUsersRows() throws Exception {
    Response response = get("/api/v1/records");
    ListRecordsResponse list =
        PrudentTest.decode(PrudentTest.JSON, response, ListRecordsResponse.newBuilder()).build();
    assertEquals(0, list.getRecordsCount());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void record_update_isNotFoundAndChangesNothing() throws Exception {
    UUID alicesAccount = PrudentTest.seedAccount(PrudentTest.ALICE, "Alice's wallet", "PLN");
    UUID alicesCategory = PrudentTest.seedCategory(PrudentTest.ALICE, "Alice's food");

    UpdateRecordRequest hijack =
        UpdateRecordRequest.newBuilder()
            .setTitle("Taken over")
            .setAmountMinor(1L)
            .setDate("2026-08-17")
            .setCategoryId(alicesCategory.toString())
            .setAccountId(alicesAccount.toString())
            .setCurrency("PLN")
            .build();

    Response response =
        PrudentTest.body(PrudentTest.request(PrudentTest.JSON), PrudentTest.JSON, hijack)
            .when()
            .put("/api/v1/records/" + bobsRecord)
            .andReturn();

    assertEquals(404, response.statusCode());
    assertEquals(
        99_00L,
        QuarkusTransaction.requiringNew()
            .call(() -> RecordEntity.<RecordEntity>findById(bobsRecord).amountMinor),
        "the other user's record must be untouched — amount included");
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void record_delete_isNotFoundAndDeletesNothing() {
    assertEquals(
        404,
        PrudentTest.request(PrudentTest.JSON)
            .when()
            .delete("/api/v1/records/" + bobsRecord)
            .andReturn()
            .statusCode());
    assertTrue(
        QuarkusTransaction.requiringNew().call(() -> RecordEntity.findById(bobsRecord) != null));
  }

  // -----------------------------------------------------------------------------------------
  // Cross-resource: a create cannot borrow another user's rows
  // -----------------------------------------------------------------------------------------

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void create_cannotReferenceTheOtherUsersAccountOrCategory() throws Exception {
    // A create names its account and category by id in the BODY, which is the one place a client
    // gets to point at a row it did not fetch. Both are looked up as the caller's.
    CreateAccountRequest ownAccount =
        CreateAccountRequest.newBuilder()
            .setName("Alice's wallet")
            .setType(AccountType.ACCOUNT_TYPE_CASH)
            .addBalances(CurrencyBalance.newBuilder().setCurrency("PLN").setAmountMinor(0L))
            .build();
    PrudentTest.body(PrudentTest.request(PrudentTest.JSON), PrudentTest.JSON, ownAccount)
        .when()
        .post("/api/v1/accounts")
        .andReturn();

    Response response =
        PrudentTest.body(
                PrudentTest.request(PrudentTest.JSON),
                PrudentTest.JSON,
                CreateRecordRequest.newBuilder()
                    .setTitle("Into Bob's account")
                    .setAmountMinor(1_00L)
                    .setDate("2026-08-17")
                    .setCategoryId(bobsCategory.toString())
                    .setAccountId(bobsAccount.toString())
                    .setCurrency("PLN")
                    .build())
            .when()
            .post("/api/v1/records")
            .andReturn();

    assertEquals(400, response.statusCode());
    assertEquals(
        1L,
        QuarkusTransaction.requiringNew().call(() -> RecordEntity.count("accountId", bobsAccount)),
        "the other user's account must still hold only its own seeded record");
  }

  private static Response get(String path) {
    return PrudentTest.request(PrudentTest.JSON).when().get(path).andReturn();
  }

  private static void assertNotFoundBody(Response response) throws Exception {
    ZenError error =
        PrudentTest.decode(PrudentTest.JSON, response, ZenError.newBuilder()).build();
    assertEquals("not_found", error.getCode());
  }
}
