package prudent.server;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.security.TestSecurity;
import io.restassured.response.Response;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import prudent.proto.v1.Account;
import prudent.proto.v1.AccountType;
import prudent.proto.v1.CreateAccountRequest;
import prudent.proto.v1.CurrencyBalance;
import prudent.proto.v1.ListAccountsResponse;
import prudent.proto.v1.UpdateAccountRequest;
import zen.proto.v1.ZenError;

/**
 * The account surface: CRUD in both transport modes, and the multi-currency rules ADR-008 could not
 * express in the message itself.
 */
@QuarkusTest
class AccountResourceTest {

  @BeforeEach
  void reset() {
    PrudentTest.reset();
  }

  private static CurrencyBalance balance(String currency, long amountMinor) {
    return CurrencyBalance.newBuilder().setCurrency(currency).setAmountMinor(amountMinor).build();
  }

  @ParameterizedTest
  @ValueSource(strings = {PrudentTest.JSON, PrudentTest.PROTOBUF})
  @TestSecurity(user = PrudentTest.ALICE)
  void crud_roundTripsWithSeveralCurrencies(String mode) throws Exception {
    CreateAccountRequest create =
        CreateAccountRequest.newBuilder()
            .setName("Travel card")
            .setType(AccountType.ACCOUNT_TYPE_CARD)
            .setIsActive(true)
            .setIncludeInTotal(true)
            .setIncludeInOverview(true)
            .addBalances(balance("PLN", 125_00L))
            .addBalances(balance("EUR", 40_00L))
            .addBalances(balance("USD", 0L))
            .build();

    Response created =
        PrudentTest.body(PrudentTest.request(mode), mode, create)
            .when()
            .post("/api/v1/accounts")
            .andReturn();
    assertEquals(201, created.statusCode());
    Account account = PrudentTest.decode(mode, created, Account.newBuilder()).build();

    assertFalse(account.getId().isBlank(), "the create response must carry a server-minted id");
    assertEquals(AccountType.ACCOUNT_TYPE_CARD, account.getType());

    // THE ORDER THE SERVER SENT. A repeated field is a list, and the client renders it in order —
    // so the declared order is stored rather than left to whatever order rows come back in.
    assertEquals(
        List.of("PLN", "EUR", "USD"),
        account.getBalancesList().stream().map(CurrencyBalance::getCurrency).toList());
    // A ZERO-AMOUNT POCKET SURVIVES. amount_minor = 0 is the proto3 default and is absent from both
    // encodings, so the USD entry rides entirely on its currency — an account holding a currency
    // with nothing in it is a real state, not a missing one.
    assertEquals(0L, account.getBalances(2).getAmountMinor());
    assertEquals(125_00L, account.getBalances(0).getAmountMinor());

    // READ + LIST
    Response read =
        PrudentTest.request(mode).when().get("/api/v1/accounts/" + account.getId()).andReturn();
    assertEquals(200, read.statusCode());
    assertEquals(account, PrudentTest.decode(mode, read, Account.newBuilder()).build());

    Response listed = PrudentTest.request(mode).when().get("/api/v1/accounts").andReturn();
    ListAccountsResponse list =
        PrudentTest.decode(mode, listed, ListAccountsResponse.newBuilder()).build();
    assertEquals(1, list.getAccountsCount());

    // UPDATE — adding a currency is always allowed; that is how an account becomes multi-currency
    // after the fact.
    UpdateAccountRequest update =
        UpdateAccountRequest.newBuilder()
            .setName("Travel card")
            .setType(AccountType.ACCOUNT_TYPE_CARD)
            .setIsActive(true)
            .setIncludeInTotal(true)
            .setIncludeInOverview(true)
            .addBalances(balance("PLN", 125_00L))
            .addBalances(balance("EUR", 40_00L))
            .addBalances(balance("USD", 0L))
            .addBalances(balance("GBP", 15_00L))
            .build();
    Response updated =
        PrudentTest.body(PrudentTest.request(mode), mode, update)
            .when()
            .put("/api/v1/accounts/" + account.getId())
            .andReturn();
    assertEquals(200, updated.statusCode());
    assertEquals(
        4, PrudentTest.decode(mode, updated, Account.newBuilder()).build().getBalancesCount());

    // DELETE
    Response deleted =
        PrudentTest.request(mode).when().delete("/api/v1/accounts/" + account.getId()).andReturn();
    assertEquals(204, deleted.statusCode());
  }

  @ParameterizedTest
  @ValueSource(strings = {PrudentTest.JSON, PrudentTest.PROTOBUF})
  @TestSecurity(user = PrudentTest.ALICE)
  void unspecifiedType_isRejected(String mode) throws Exception {
    // ACCOUNT_TYPE_UNSPECIFIED is what proto3 decodes an omitted field to. Defaulting it to cash
    // would make "the client forgot" indistinguishable from "the client meant cash", and cash is a
    // valid answer — so it is refused rather than interpreted.
    CreateAccountRequest create =
        CreateAccountRequest.newBuilder()
            .setName("Nameless kind")
            .addBalances(balance("PLN", 0L))
            .build();

    Response response =
        PrudentTest.body(PrudentTest.request(mode), mode, create)
            .when()
            .post("/api/v1/accounts")
            .andReturn();

    assertEquals(400, response.statusCode());
    assertEquals(
        "invalid", PrudentTest.decode(mode, response, ZenError.newBuilder()).build().getCode());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void emptyBalances_areRejected() throws Exception {
    CreateAccountRequest create =
        CreateAccountRequest.newBuilder()
            .setName("Holds nothing")
            .setType(AccountType.ACCOUNT_TYPE_CASH)
            .build();

    Response response =
        PrudentTest.body(PrudentTest.request(PrudentTest.JSON), PrudentTest.JSON, create)
            .when()
            .post("/api/v1/accounts")
            .andReturn();

    assertEquals(400, response.statusCode());
    ZenError error =
        PrudentTest.decode(PrudentTest.JSON, response, ZenError.newBuilder()).build();
    assertEquals("invalid", error.getCode());
    assertTrue(error.getMessage().toLowerCase().contains("currency"));
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void duplicateCurrency_isRejectedRatherThanMerged() throws Exception {
    // Merging would silently pick one amount and discard the other, and the user would see a
    // balance they never entered.
    CreateAccountRequest create =
        CreateAccountRequest.newBuilder()
            .setName("Twice PLN")
            .setType(AccountType.ACCOUNT_TYPE_CASH)
            .addBalances(balance("PLN", 10_00L))
            .addBalances(balance("PLN", 25_00L))
            .build();

    Response response =
        PrudentTest.body(PrudentTest.request(PrudentTest.JSON), PrudentTest.JSON, create)
            .when()
            .post("/api/v1/accounts")
            .andReturn();

    assertEquals(400, response.statusCode());
    assertTrue(
        PrudentTest.decode(PrudentTest.JSON, response, ZenError.newBuilder())
            .build()
            .getMessage()
            .contains("PLN"));
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void invalidCurrency_isRejected() throws Exception {
    CreateAccountRequest create =
        CreateAccountRequest.newBuilder()
            .setName("Galactic credits")
            .setType(AccountType.ACCOUNT_TYPE_CASH)
            .addBalances(balance("XYZ", 100L))
            .build();

    Response response =
        PrudentTest.body(PrudentTest.request(PrudentTest.JSON), PrudentTest.JSON, create)
            .when()
            .post("/api/v1/accounts")
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
  void droppingACurrencyThatHasRecords_isRefused() throws Exception {
    UUID accountId = PrudentTest.seedAccount(PrudentTest.ALICE, "Wallet", "PLN", "EUR");
    UUID categoryId = PrudentTest.seedCategory(PrudentTest.ALICE, "Food");
    PrudentTest.seedRecord(PrudentTest.ALICE, accountId, categoryId, 50_00L, "EUR");

    // A full replacement omitting EUR is a request to remove it — which would orphan money that
    // left an account no longer admitting it exists.
    UpdateAccountRequest update =
        UpdateAccountRequest.newBuilder()
            .setName("Wallet")
            .setType(AccountType.ACCOUNT_TYPE_CASH)
            .setIsActive(true)
            .addBalances(balance("PLN", 0L))
            .build();

    Response response =
        PrudentTest.body(PrudentTest.request(PrudentTest.JSON), PrudentTest.JSON, update)
            .when()
            .put("/api/v1/accounts/" + accountId)
            .andReturn();

    assertEquals(409, response.statusCode());
    ZenError error =
        PrudentTest.decode(PrudentTest.JSON, response, ZenError.newBuilder()).build();
    assertEquals("conflict", error.getCode());
    assertTrue(error.getMessage().contains("EUR"));
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void deletingAnAccountThatHasRecords_isRefused() throws Exception {
    UUID accountId = PrudentTest.seedAccount(PrudentTest.ALICE, "Wallet", "PLN");
    UUID categoryId = PrudentTest.seedCategory(PrudentTest.ALICE, "Food");
    PrudentTest.seedRecord(PrudentTest.ALICE, accountId, categoryId, 10_00L, "PLN");

    Response response =
        PrudentTest.request(PrudentTest.JSON)
            .when()
            .delete("/api/v1/accounts/" + accountId)
            .andReturn();

    assertEquals(409, response.statusCode());
    assertEquals(
        "conflict",
        PrudentTest.decode(PrudentTest.JSON, response, ZenError.newBuilder()).build().getCode());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void settingADefault_clearsThePreviousHolder() throws Exception {
    UUID first = PrudentTest.seedAccount(PrudentTest.ALICE, "First", "PLN");

    CreateAccountRequest makeDefault =
        CreateAccountRequest.newBuilder()
            .setName("Second")
            .setType(AccountType.ACCOUNT_TYPE_CASH)
            .setIsDefault(true)
            .addBalances(balance("PLN", 0L))
            .build();
    PrudentTest.body(PrudentTest.request(PrudentTest.JSON), PrudentTest.JSON, makeDefault)
        .when()
        .post("/api/v1/accounts")
        .andReturn();

    // Promote the first one; the server must clear the flag on the second rather than trusting the
    // client to have sent a matching update for it.
    UpdateAccountRequest promote =
        UpdateAccountRequest.newBuilder()
            .setName("First")
            .setType(AccountType.ACCOUNT_TYPE_CASH)
            .setIsDefault(true)
            .addBalances(balance("PLN", 0L))
            .build();
    PrudentTest.body(PrudentTest.request(PrudentTest.JSON), PrudentTest.JSON, promote)
        .when()
        .put("/api/v1/accounts/" + first)
        .andReturn();

    Response listed =
        PrudentTest.request(PrudentTest.JSON).when().get("/api/v1/accounts").andReturn();
    ListAccountsResponse list =
        PrudentTest.decode(PrudentTest.JSON, listed, ListAccountsResponse.newBuilder()).build();

    assertEquals(
        1,
        list.getAccountsList().stream().filter(Account::getIsDefault).count(),
        "exactly one account may be the default");
    assertEquals(
        first.toString(),
        list.getAccountsList().stream().filter(Account::getIsDefault).findFirst().orElseThrow().getId());
  }
}
