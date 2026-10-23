package prudent.privacy;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.google.protobuf.TextFormat;
import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.security.TestSecurity;
import io.restassured.response.Response;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import prudent.PrudentTest;
import prudent.privacy.PrivacySeed.Seeded;
import prudent.proto.v1.Account;
import prudent.proto.v1.BudgetCarryOverReset;
import prudent.proto.v1.Category;
import prudent.proto.v1.DataExport;
import prudent.proto.v1.Goal;
import prudent.proto.v1.GoalStatus;

/**
 * {@code GET /api/v1/privacy/export}: that what a person is handed is <em>readable</em>, is
 * <em>all</em> of what they own, and is <em>only</em> theirs.
 *
 * <p>The three are separate failures with separate consequences, so each has its own test. A
 * readable export that omits archived rows is a person told "this is everything" when it is not; a
 * complete one that includes a neighbour's account is a breach.
 */
@QuarkusTest
class PrivacyExportTest {

  private Seeded alice;
  private Seeded bob;

  @BeforeEach
  void seed() {
    PrudentTest.reset();
    alice = PrivacySeed.everythingFor(PrudentTest.ALICE);
    bob = PrivacySeed.everythingFor(PrudentTest.BOB);
  }

  private Response export(String mode) {
    Response response = PrudentTest.request(mode).when().get("/api/v1/privacy/export").andReturn();
    assertEquals(200, response.statusCode(), response.asString());
    return response;
  }

  @ParameterizedTest
  @ValueSource(strings = {PrudentTest.JSON, PrudentTest.PROTOBUF})
  @TestSecurity(user = PrudentTest.ALICE)
  void exportsEveryKindOfRowTheUserOwns(String mode) throws Exception {
    DataExport data =
        PrudentTest.decode(mode, export(mode), DataExport.newBuilder()).build();

    assertEquals(1, data.getFormatVersion());
    assertTrue(data.getExportedAtMs() > 0, "an export says when it was made");
    assertEquals("alice@example.com", data.getProfile().getEmail());
    assertEquals("en", data.getProfile().getLanguage());
    assertTrue(data.hasSettings());
    assertEquals("EUR", data.getSettings().getMainCurrency());

    assertEquals(1, data.getAccountsCount());
    assertEquals(2, data.getCategoriesCount());
    assertEquals(1, data.getRecordsCount());
    assertEquals(1, data.getPlansCount());
    assertEquals(1, data.getOccurrencesCount());
    assertEquals(1, data.getBudgetsCount());
    assertEquals(2, data.getCarryOverResetsCount());
    assertEquals(2, data.getGoalsCount());
    assertEquals(1, data.getGoalAllocationsCount());

    // Figures survive the trip exactly: money is minor units, never a float.
    assertEquals(-12_34L, data.getRecords(0).getAmountMinor());
    assertEquals(100_00L, data.getGoalAllocations(0).getAmountMinor());
  }

  /**
   * "My data" is not "my data minus what the screens hide". An archived category, an archived goal
   * and a revoked reset are what a lifecycle-filtered list drops first.
   */
  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void exportsRowsInEveryLifecycleState() throws Exception {
    DataExport data =
        PrudentTest.decode(PrudentTest.JSON, export(PrudentTest.JSON), DataExport.newBuilder())
            .build();

    Category archived =
        data.getCategoriesList().stream()
            .filter(c -> c.getId().equals(alice.archivedCategory().toString()))
            .findFirst()
            .orElseThrow(() -> new AssertionError("the archived category is missing"));
    assertTrue(archived.getArchived());

    Goal archivedGoal =
        data.getGoalsList().stream()
            .filter(g -> g.getId().equals(alice.archivedGoal().toString()))
            .findFirst()
            .orElseThrow(() -> new AssertionError("the archived goal is missing"));
    assertEquals(GoalStatus.GOAL_STATUS_ARCHIVED, archivedGoal.getStatus());

    BudgetCarryOverReset revoked =
        data.getCarryOverResetsList().stream()
            .filter(r -> r.getId().equals(alice.revokedReset().toString()))
            .findFirst()
            .orElseThrow(() -> new AssertionError("the revoked reset is missing"));
    assertFalse(revoked.getRevokedBy().isEmpty(), "a revoked reset says it was revoked");
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void exportsNothingThatBelongsToAnotherUser() throws Exception {
    DataExport data =
        PrudentTest.decode(PrudentTest.JSON, export(PrudentTest.JSON), DataExport.newBuilder())
            .build();

    Set<String> bobs =
        Set.of(
            bob.account().toString(),
            bob.category().toString(),
            bob.archivedCategory().toString(),
            bob.record().toString(),
            bob.plan().toString(),
            bob.occurrence().toString(),
            bob.goal().toString(),
            bob.archivedGoal().toString(),
            bob.allocation().toString(),
            bob.liveReset().toString(),
            bob.revokedReset().toString());
    // The whole document, text and all: an id of Bob's anywhere in it is a leak, wherever it sits.
    String text = TextFormat.printer().printToString(data);
    for (String id : bobs) {
      assertFalse(text.contains(id), "Bob's row " + id + " is in Alice's export");
    }
    assertFalse(text.contains("bob@example.com"), "Bob's address is in Alice's export");
    assertEquals(
        List.of(alice.account().toString()),
        data.getAccountsList().stream().map(Account::getId).collect(Collectors.toList()));
  }

  /**
   * The point of choosing JSON as the default form: a person can open it. Parsed here as plain JSON
   * with no protobuf in the loop, and the field names are the ones the rest of the API uses.
   */
  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void theJsonFormIsPlainReadableJson() {
    Response response = export(PrudentTest.JSON);
    assertTrue(response.getContentType().startsWith("application/json"));

    Map<String, Object> document = response.jsonPath().getMap("$");
    assertEquals("alice@example.com", response.jsonPath().getString("profile.email"));
    assertEquals(1, response.jsonPath().getInt("formatVersion"));
    for (String list :
        List.of(
            "accounts", "categories", "records", "plans", "occurrences", "budgets",
            "carryOverResets", "goals", "goalAllocations")) {
      assertTrue(document.containsKey(list), "the export has no `" + list + "` list");
      assertFalse(response.jsonPath().getList(list).isEmpty(), "`" + list + "` is empty");
    }
    assertTrue(response.asString().contains("Checking of " + PrudentTest.ALICE));
  }

  /**
   * A response with someone's whole financial life in it must not be kept by a cache, the browser's
   * included.
   */
  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void theResponseIsNotCacheable() {
    assertEquals("no-store", export(PrudentTest.JSON).getHeader("Cache-Control"));
  }

  @Test
  void anAnonymousCallerIsRefused() {
    assertEquals(
        401,
        PrudentTest.request(PrudentTest.JSON)
            .when()
            .get("/api/v1/privacy/export")
            .andReturn()
            .statusCode());
  }
}
