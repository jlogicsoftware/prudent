package prudent.privacy;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
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
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import prudent.PrudentTest;
import prudent.proto.v1.EraseAccountRequest;

/**
 * Proves "export is complete and erasure removes all user-owned data" <strong>against the
 * database's own schema</strong>, so the claim does not depend on anyone remembering to update a
 * list.
 *
 * <p><strong>Why not assert the tables we know about.</strong> A test listing today's ten tables
 * passes forever while the eleventh — added next quarter, with its own {@code user_id} — is exported
 * by nothing and erased by nothing. The failure is silent and it is about personal financial data.
 * Here the tables are <em>discovered</em>: every table in the schema with a {@code user_id} column.
 * A new one has to be seeded (otherwise the first test fails, naming it), appear in the export
 * (otherwise the second fails), and be emptied by the erasure (otherwise the third fails) before
 * this suite is green again.
 *
 * <p>What the discovery cannot see is a table that stores user data <em>without</em> a
 * {@code user_id} column. The one that exists today, {@code prudent_account_balance}, hangs off its
 * account and is checked for orphans explicitly; a future one is a design decision for whoever adds
 * it, which this test's failure messages ask them to make.
 */
@QuarkusTest
class PrivacyCoverageTest {

  /**
   * Which {@code DataExport} field carries each discovered table. The one place a person adding a
   * table must say where it is exported — and a missing entry fails {@link
   * #everyUserOwnedTableIsInTheExport}, not a code review.
   */
  private static final Map<String, String> EXPORT_FIELD =
      Map.ofEntries(
          Map.entry("prudent_account", "accounts"),
          Map.entry("prudent_category", "categories"),
          Map.entry("prudent_record", "records"),
          Map.entry("prudent_plan", "plans"),
          Map.entry("prudent_plan_occurrence", "occurrences"),
          Map.entry("prudent_budget", "budgets"),
          Map.entry("prudent_budget_carry_reset", "carryOverResets"),
          Map.entry("prudent_goal", "goals"),
          Map.entry("prudent_goal_allocation", "goalAllocations"),
          Map.entry("prudent_settings", "settings"));

  @Inject EntityManager entityManager;

  @BeforeEach
  void seed() {
    PrudentTest.reset();
    PrivacySeed.everythingFor(PrudentTest.ALICE);
    PrivacySeed.everythingFor(PrudentTest.BOB);
  }

  private List<String> userOwnedTables() {
    return UserOwnedRows.tables(entityManager);
  }

  private long rowsOf(String table, String userId) {
    return UserOwnedRows.rowsOf(entityManager, table, userId);
  }

  @Test
  void discoveryFindsTheTablesThisSuiteDependsOn() {
    // Not vacuity for its own sake: were the information_schema query to return nothing, every
    // assertion below would pass over an empty list and prove nothing at all.
    assertTrue(
        userOwnedTables().size() >= EXPORT_FIELD.size(),
        "the schema query found " + userOwnedTables() + " — fewer tables than are known to exist");
  }

  @Test
  void everyUserOwnedTableIsSeeded() {
    for (String table : userOwnedTables()) {
      assertTrue(
          rowsOf(table, PrudentTest.ALICE) > 0,
          table
              + " holds per-user data but PrivacySeed gives a user no row in it, so neither the"
              + " export nor the erasure of it is tested — seed it in PrivacySeed");
    }
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void everyUserOwnedTableIsInTheExport() {
    Response response =
        PrudentTest.request(PrudentTest.JSON).when().get("/api/v1/privacy/export").andReturn();
    assertEquals(200, response.statusCode(), response.asString());

    Map<String, Long> missing = new TreeMap<>();
    for (String table : userOwnedTables()) {
      String field = EXPORT_FIELD.get(table);
      assertTrue(
          field != null,
          table
              + " holds per-user data but has no field in DataExport — add it to privacy.proto, to"
              + " PrudentDataExporter, and to EXPORT_FIELD here");
      long exported =
          "settings".equals(field)
              ? (response.jsonPath().get(field) == null ? 0 : 1)
              : response.jsonPath().getList(field).size();
      long stored = rowsOf(table, PrudentTest.ALICE);
      if (exported != stored) {
        missing.put(table + " (export field `" + field + "`)", stored - exported);
      }
    }
    assertTrue(missing.isEmpty(), "the export holds fewer rows than the database does: " + missing);
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void erasureLeavesNothingInAnyUserOwnedTableAndTouchesNoOneElse() throws Exception {
    Map<String, Long> bobBefore = new TreeMap<>();
    for (String table : userOwnedTables()) {
      bobBefore.put(table, rowsOf(table, PrudentTest.BOB));
    }

    Response response =
        PrudentTest.body(
                PrudentTest.request(PrudentTest.JSON),
                PrudentTest.JSON,
                EraseAccountRequest.newBuilder().setConfirmEmail("alice@example.com").build())
            .when()
            .post("/api/v1/privacy/erase")
            .andReturn();
    assertEquals(204, response.statusCode(), response.asString());

    for (String table : userOwnedTables()) {
      assertEquals(
          0,
          rowsOf(table, PrudentTest.ALICE),
          table + " still holds rows for an erased user — add it to PrudentDataEraser");
      assertEquals(
          bobBefore.get(table),
          rowsOf(table, PrudentTest.BOB),
          table + " lost rows belonging to a user who was not erased");
    }
    assertEquals(0, orphanedBalances(), "account balances outlived their accounts");
    assertFalse(bobBefore.isEmpty());
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
