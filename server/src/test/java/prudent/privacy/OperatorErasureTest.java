package prudent.privacy;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.quarkus.narayana.jta.QuarkusTransaction;
import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.security.TestSecurity;
import io.restassured.response.Response;
import jakarta.inject.Inject;
import jakarta.persistence.EntityManager;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;
import java.util.UUID;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.logging.Handler;
import java.util.logging.LogRecord;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import prudent.PrudentTest;
import zen.identity.user.User;
import zen.identity.user.UserRetentionService;
import zen.identity.user.UserRole;

/**
 * {@code POST /api/v1/admin/privacy/users/{userId}/erase}: an operator erases a person who cannot
 * sign in — that only an admin can, that it removes exactly what the person's own erasure removes
 * and nobody else's, and that its log line names an opaque id and counts.
 *
 * <p>Alice is the operator and Bob is the person being erased. The admin role is minted with
 * {@code @TestSecurity}, as jZen's own admin suites do; that {@code RoleAugmentor} resolves it from
 * the {@code users} table is proven upstream by {@code RoleAugmentorTest}. The tables are discovered from
 * the database's own schema, as in {@link PrivacyCoverageTest}, so a table added tomorrow is held
 * to this route as well.
 */
@QuarkusTest
class OperatorErasureTest {

  @Inject EntityManager entityManager;

  private final CopyOnWriteArrayList<String> logged = new CopyOnWriteArrayList<>();
  private Handler capture;

  @BeforeEach
  void seed() {
    PrudentTest.reset();
    PrivacySeed.everythingFor(PrudentTest.ALICE);
    PrivacySeed.everythingFor(PrudentTest.BOB);

    capture =
        new Handler() {
          @Override
          public void publish(LogRecord record) {
            String line = record.getMessage();
            Object[] params = record.getParameters();
            if (params != null && params.length > 0) {
              try {
                line = String.format(record.getMessage(), params);
              } catch (RuntimeException notPrintf) {
                line = record.getMessage() + " " + java.util.Arrays.toString(params);
              }
            }
            logged.add(line);
          }

          @Override
          public void flush() {}

          @Override
          public void close() {}
        };
    java.util.logging.Logger.getLogger("").addHandler(capture);
  }

  @AfterEach
  void releaseLogs() {
    java.util.logging.Logger.getLogger("").removeHandler(capture);
  }

  private Response erase(String mode, String userId) {
    return PrudentTest.request(mode).when().post("/api/v1/admin/privacy/users/" + userId + "/erase");
  }

  private List<String> userOwnedTables() {
    @SuppressWarnings("unchecked")
    List<String> tables =
        QuarkusTransaction.requiringNew()
            .call(
                () ->
                    entityManager
                        .createNativeQuery(
                            "select table_name from information_schema.columns"
                                + " where table_schema = 'public' and column_name = 'user_id'"
                                + " order by table_name")
                        .getResultList());
    return tables;
  }

  private long rowsOf(String table, String userId) {
    return QuarkusTransaction.requiringNew()
        .call(
            () ->
                ((Number)
                        entityManager
                            // The table name comes from information_schema, never from input.
                            .createNativeQuery(
                                "select count(*) from " + table + " where user_id = ?1")
                            .setParameter(1, UUID.fromString(userId))
                            .getSingleResult())
                    .longValue());
  }

  private Map<String, Long> rowsOfEveryTable(String userId) {
    Map<String, Long> rows = new TreeMap<>();
    for (String table : userOwnedTables()) {
      rows.put(table, rowsOf(table, userId));
    }
    return rows;
  }

  @ParameterizedTest
  @ValueSource(strings = {PrudentTest.JSON, PrudentTest.PROTOBUF})
  @TestSecurity(user = PrudentTest.ALICE, roles = UserRole.Names.ADMIN)
  void anOperatorEmptiesEveryUserOwnedTableForThePersonAndTouchesNoOneElse(String mode) {
    Map<String, Long> aliceBefore = rowsOfEveryTable(PrudentTest.ALICE);
    for (String table : userOwnedTables()) {
      assertTrue(rowsOf(table, PrudentTest.BOB) > 0, table + " is not seeded for the person");
    }

    Response response = erase(mode, PrudentTest.BOB);

    assertEquals(204, response.statusCode(), response.asString());
    for (String table : userOwnedTables()) {
      assertEquals(
          0,
          rowsOf(table, PrudentTest.BOB),
          table + " still holds rows for an erased person — add it to PrudentDataEraser");
    }
    assertEquals(aliceBefore, rowsOfEveryTable(PrudentTest.ALICE), "the operator's rows changed");
    assertEquals(0, orphanedBalances(), "account balances outlived their accounts");
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE, roles = UserRole.Names.ADMIN)
  void theProfileIsAnonymisedAsTheFrameworkDoesIt() {
    assertEquals(204, erase(PrudentTest.JSON, PrudentTest.BOB).statusCode());

    QuarkusTransaction.requiringNew()
        .run(
            () -> {
              User profile = User.findById(UUID.fromString(PrudentTest.BOB));
              assertNotNull(profile, "the profile row is kept, as it is for dormancy");
              assertTrue(UserRetentionService.isAnonymised(profile));
              assertFalse(profile.email.contains("bob"));
              User operator = User.findById(UUID.fromString(PrudentTest.ALICE));
              assertEquals("alice@example.com", operator.email);
            });
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE, roles = UserRole.Names.ADMIN)
  void repeatingItForAnErasedPersonSucceedsAndDeletesNothingMore() {
    assertEquals(204, erase(PrudentTest.JSON, PrudentTest.BOB).statusCode());
    assertEquals(204, erase(PrudentTest.JSON, PrudentTest.BOB).statusCode());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE, roles = UserRole.Names.ADMIN)
  void anOperatorCannotEraseThemselvesThisWay() {
    Map<String, Long> before = rowsOfEveryTable(PrudentTest.ALICE);

    Response response = erase(PrudentTest.JSON, PrudentTest.ALICE);

    assertEquals(400, response.statusCode(), response.asString());
    assertEquals(before, rowsOfEveryTable(PrudentTest.ALICE), "a refused erasure deleted data");
  }

  @ParameterizedTest
  @ValueSource(strings = {"cccccccc-0000-0000-0000-00000000000c", "not-a-uuid"})
  @TestSecurity(user = PrudentTest.ALICE, roles = UserRole.Names.ADMIN)
  void anIdWithNothingBehindItIsNotFound(String unknown) {
    Map<String, Long> bobBefore = rowsOfEveryTable(PrudentTest.BOB);

    Response response = erase(PrudentTest.JSON, unknown);

    assertEquals(404, response.statusCode(), response.asString());
    assertEquals(bobBefore, rowsOfEveryTable(PrudentTest.BOB));
  }

  /**
   * Data can outlive its profile row; the route must still be able to remove it, since "the person
   * cannot sign in" is exactly when a profile may be missing.
   */
  @Test
  @TestSecurity(user = PrudentTest.ALICE, roles = UserRole.Names.ADMIN)
  void erasesDataThatHasNoProfileRowLeftBehindIt() {
    UUID orphan = UUID.randomUUID();
    PrudentTest.seedCategory(orphan.toString(), "Orphaned");

    Response response = erase(PrudentTest.JSON, orphan.toString());

    assertEquals(204, response.statusCode(), response.asString());
    assertEquals(0, rowsOf("prudent_category", orphan.toString()));
  }

  @Test
  @TestSecurity(user = PrudentTest.BOB)
  void anOrdinaryUserIsRefusedAndNothingIsDeleted() {
    Map<String, Long> aliceBefore = rowsOfEveryTable(PrudentTest.ALICE);

    Response response = erase(PrudentTest.JSON, PrudentTest.ALICE);

    assertEquals(403, response.statusCode(), response.asString());
    assertEquals(aliceBefore, rowsOfEveryTable(PrudentTest.ALICE));
  }

  @Test
  void anAnonymousCallerIsRefusedAndNothingIsDeleted() {
    Map<String, Long> bobBefore = rowsOfEveryTable(PrudentTest.BOB);

    assertEquals(401, erase(PrudentTest.JSON, PrudentTest.BOB).statusCode());
    assertEquals(bobBefore, rowsOfEveryTable(PrudentTest.BOB));
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE, roles = UserRole.Names.ADMIN)
  void theLogNamesOpaqueIdsAndCountsAndNothingOfThePerson() {
    assertEquals(204, erase(PrudentTest.JSON, PrudentTest.BOB).statusCode());

    List<String> about = logged.stream().filter(l -> l.contains(PrudentTest.BOB)).toList();
    assertFalse(about.isEmpty(), "the erasure was not logged against the person's id");
    assertTrue(
        about.stream().anyMatch(l -> l.contains("operator " + PrudentTest.ALICE)),
        "the operator's id is not in the log: " + about);
    assertTrue(
        about.stream().anyMatch(l -> l.matches(".*\\d+ record\\(s\\).*")),
        "the row counts are not in the log: " + about);
    for (String line : logged) {
      assertFalse(line.contains("bob@example.com"), "an address reached a log: " + line);
      assertFalse(line.contains("Holiday"), "a goal name reached a log: " + line);
      assertFalse(line.contains("Food"), "a category name reached a log: " + line);
    }
  }

  /** {@code prudent_account_balance} has no {@code user_id}; it is owned through its account. */
  private long orphanedBalances() {
    return QuarkusTransaction.requiringNew()
        .call(
            () ->
                ((Number)
                        entityManager
                            .createNativeQuery(
                                "select count(*) from prudent_account_balance b"
                                    + " where not exists"
                                    + " (select 1 from prudent_account a where a.id = b.account_id)")
                            .getSingleResult())
                    .longValue());
  }
}
