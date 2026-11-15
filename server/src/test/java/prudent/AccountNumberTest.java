package prudent;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.quarkus.narayana.jta.QuarkusTransaction;
import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.security.TestSecurity;
import io.restassured.response.Response;
import jakarta.inject.Inject;
import java.sql.Connection;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.UUID;
import javax.sql.DataSource;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import prudent.account.AccountEntity;
import prudent.account.AccountNumbers;
import prudent.error.PrudentException;
import prudent.proto.v1.Account;
import prudent.proto.v1.AccountType;
import prudent.proto.v1.CreateAccountRequest;
import prudent.proto.v1.CurrencyBalance;
import prudent.proto.v1.UpdateAccountRequest;
import zen.proto.v1.ZenError;

/**
 * The optional bank number of an account (M6, ADR-090, V20261114100000): how it is normalised, that
 * the resource stores it, refuses a malformed or repeated one and never echoes it, and that the
 * schema backs both rules up.
 */
@QuarkusTest
class AccountNumberTest {

  private static final String NORMAL = "00000000000000000000000001";

  @Inject DataSource dataSource;

  @BeforeEach
  void reset() {
    PrudentTest.reset();
  }

  // --- normalisation ------------------------------------------------------------------------------

  @Test
  void normalisation_removesSpacesUpperCasesAndDropsAPolishPrefix() {
    assertEquals(NORMAL, AccountNumbers.normalize("00 0000 0000 0000 0000 0000 0001"));
    assertEquals(NORMAL, AccountNumbers.normalize("  pl00000000000000000000000001 "));
    assertEquals("DE89370400440532013000", AccountNumbers.normalize("de89 3704 0044 0532 0130 00"));
    assertEquals(NORMAL, AccountNumbers.normalize("00\u00a00000\u202f0000 0000 0000 0000 0001"));
    assertNull(AccountNumbers.normalize("\u00a0\u202f"), "only unicode spaces is blank, not malformed");
    assertNull(AccountNumbers.normalize(null));
    assertNull(AccountNumbers.normalize("   "));
  }

  @Test
  void normalisation_refusesWhatIsNotANumbersShape_withoutEchoingIt() {
    for (String bad : new String[] {"12345", "00-0000-0000-0000", "x".repeat(35), "00 0000 000é"}) {
      PrudentException e = assertThrows(PrudentException.class, () -> AccountNumbers.normalize(bad));
      assertTrue(!e.getMessage().contains(bad.trim()), e.getMessage());
    }
  }

  @Test
  void upperCasingFoldsAsciiOnly_soTwoDifferentStringsAreNeverOneNumber() {
    // "ß" would become "SS", a dotless "ı" "I" and a long "ſ" "S" under String.toUpperCase: each
    // would then pass the shape check as a number the user never typed.
    String sharp = "00000000ß000000000001"; // 21 chars; "SS" would make it 22
    String ss = "00000000SS000000000001";
    for (String folded : new String[] {sharp, "0000000000ı000000000", "0000000000ſ000000000"}) {
      assertNull(AccountNumbers.normalizeOrNull(folded), folded);
      assertThrows(PrudentException.class, () -> AccountNumbers.normalize(folded), folded);
    }
    assertEquals(ss, AccountNumbers.normalize(ss.toLowerCase(java.util.Locale.ROOT)));
    assertTrue(!AccountNumbers.identityOf(sharp).equals(AccountNumbers.identityOf(ss)));
    assertEquals(AccountNumbers.identityOf("pl00000000000000000000000001"), AccountNumbers.identityOf(NORMAL));
  }

  @Test
  void aUniqueViolationAnywhereInTheCauseChain_isRecognised() {
    SQLException violation = new SQLException("x", "23505");
    assertTrue(
        prudent.account.AccountResource.isUniqueViolation(
            new jakarta.persistence.PersistenceException(
                new org.hibernate.exception.ConstraintViolationException("m", violation, "prudent_account_number_unique"))));
    assertTrue(!prudent.account.AccountResource.isUniqueViolation(new jakarta.persistence.PersistenceException(new SQLException("x", "23514"))));
  }

  // --- the resource -----------------------------------------------------------------------------

  private static CurrencyBalance pln() {
    return CurrencyBalance.newBuilder().setCurrency("PLN").build();
  }

  private static Response create(String number) throws Exception {
    CreateAccountRequest request =
        CreateAccountRequest.newBuilder()
            .setName("Checking " + UUID.randomUUID())
            .setType(AccountType.ACCOUNT_TYPE_CHECKING)
            .setIsActive(true)
            .setAccountNumber(number)
            .addBalances(pln())
            .build();
    return PrudentTest.body(PrudentTest.request(PrudentTest.JSON), PrudentTest.JSON, request)
        .when()
        .post("/api/v1/accounts")
        .andReturn();
  }

  private static Account account(Response response) throws Exception {
    assertEquals(201, response.statusCode(), response.asString());
    return PrudentTest.decode(PrudentTest.JSON, response, Account.newBuilder()).build();
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void create_storesTheNormalisedNumber_andAnAccountMayHaveNone() throws Exception {
    assertEquals(NORMAL, account(create("00 0000 0000 0000 0000 0000 0001")).getAccountNumber());
    assertEquals("", account(create("")).getAccountNumber());
    assertEquals("", account(create("  ")).getAccountNumber(), "blank is none, not an error");
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aMalformedNumber_isA400_andNeverEchoed() throws Exception {
    Response response = create("SECRET-12");
    assertEquals(400, response.statusCode(), response.asString());
    ZenError error = PrudentTest.decode(PrudentTest.JSON, response, ZenError.newBuilder()).build();
    assertTrue(!error.getMessage().contains("SECRET"), error.getMessage());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aNumberAnotherOfTheUsersAccountsHolds_isA409_underAnySpelling() throws Exception {
    account(create(NORMAL));
    Response repeated = create("PL 00 0000 0000 0000 0000 0000 0001");
    assertEquals(409, repeated.statusCode(), repeated.asString());
    ZenError error =
        PrudentTest.decode(PrudentTest.JSON, repeated, ZenError.newBuilder()).build();
    assertTrue(!error.getMessage().contains("0001"), error.getMessage());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void update_isAFullReplacement_soOmittingTheNumberRemovesIt_andResendingItKeepsIt()
      throws Exception {
    Account created = account(create(NORMAL));
    UpdateAccountRequest.Builder update =
        UpdateAccountRequest.newBuilder()
            .setName(created.getName())
            .setType(AccountType.ACCOUNT_TYPE_CHECKING)
            .setIsActive(true)
            .addBalances(pln());

    Response kept =
        PrudentTest.body(
                PrudentTest.request(PrudentTest.JSON),
                PrudentTest.JSON,
                update.setAccountNumber(NORMAL).build())
            .when()
            .put("/api/v1/accounts/" + created.getId())
            .andReturn();
    assertEquals(NORMAL, PrudentTest.decode(PrudentTest.JSON, kept, Account.newBuilder()).build().getAccountNumber());

    // Saving the account's own number again is not a clash with itself.
    Response cleared =
        PrudentTest.body(
                PrudentTest.request(PrudentTest.JSON),
                PrudentTest.JSON,
                update.clearAccountNumber().build())
            .when()
            .put("/api/v1/accounts/" + created.getId())
            .andReturn();
    assertEquals(200, cleared.statusCode(), cleared.asString());
    assertEquals("", PrudentTest.decode(PrudentTest.JSON, cleared, Account.newBuilder()).build().getAccountNumber());
  }

  @Test
  void twoUsersMayHoldTheSameNumber() {
    UUID alice = PrudentTest.seedAccount(PrudentTest.ALICE, "A", "PLN");
    UUID bob = PrudentTest.seedAccount(PrudentTest.BOB, "B", "PLN");
    QuarkusTransaction.requiringNew()
        .run(
            () -> {
              AccountEntity.<AccountEntity>findById(alice).accountNumber = NORMAL;
              AccountEntity.<AccountEntity>findById(bob).accountNumber = NORMAL;
            });
    UUID foundForAlice =
        QuarkusTransaction.requiringNew()
            .call(() -> AccountEntity.findOwnedByNumber(UUID.fromString(PrudentTest.ALICE), NORMAL).id);
    UUID foundForBob =
        QuarkusTransaction.requiringNew()
            .call(() -> AccountEntity.findOwnedByNumber(UUID.fromString(PrudentTest.BOB), NORMAL).id);
    assertEquals(alice, foundForAlice);
    assertEquals(bob, foundForBob);
  }

  // --- the schema backs the rules up --------------------------------------------------------------

  @Test
  void theSchemaRefusesAMalformedNumber_aRepeatedOne_andAcceptsNone() throws SQLException {
    UUID first = UUID.randomUUID();
    UUID second = UUID.randomUUID();
    try (Connection owner = dataSource.getConnection();
        Statement statement = owner.createStatement()) {
      String insert =
          "INSERT INTO prudent_account (id, user_id, name, kind, account_number) VALUES ('%s', '"
              + PrudentTest.ALICE
              + "', 'x', 'CASH', %s)";
      statement.executeUpdate(String.format(insert, first, "NULL"));
      statement.executeUpdate(String.format(insert, second, "NULL")); // none may repeat
      statement.executeUpdate("UPDATE prudent_account SET account_number = '" + NORMAL + "' WHERE id = '" + first + "'");

      assertThrows(
          SQLException.class,
          () ->
              statement.executeUpdate(
                  "UPDATE prudent_account SET account_number = '" + NORMAL + "' WHERE id = '" + second + "'"));
      assertThrows(
          SQLException.class,
          () ->
              statement.executeUpdate(
                  "UPDATE prudent_account SET account_number = 'lower case 12345' WHERE id = '" + second + "'"));
    }
  }
}
