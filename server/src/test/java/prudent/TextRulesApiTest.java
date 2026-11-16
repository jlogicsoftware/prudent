package prudent;

import static org.junit.jupiter.api.Assertions.assertEquals;

import io.quarkus.narayana.jta.QuarkusTransaction;
import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.security.TestSecurity;
import io.restassured.response.Response;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import prudent.account.AccountBalance;
import prudent.account.AccountEntity;
import prudent.account.AccountKind;
import prudent.goal.FreeMoney;
import prudent.proto.v1.Account;
import prudent.proto.v1.Category;
import prudent.proto.v1.ListAccountsResponse;
import prudent.proto.v1.ListCategoriesResponse;
import prudent.proto.v1.ListRecordsResponse;
import prudent.proto.v1.Record;
import prudent.record.RecordEntity;

/**
 * The text rules of ADR-106 through the routes a person uses: the record search and the order of
 * account and category names. Each case here fails on the database-collated, SQL-{@code LIKE}
 * behaviour it replaced; the rules themselves are pinned by {@code TextRulesTest}.
 *
 * <p>Ukrainian names are written as Unicode escapes: the repository publishes English text, and
 * these are test data, not product strings.
 */
@QuarkusTest
class TextRulesApiTest {

  /** Ukrainian "food", capital Yi first. */
  private static final String UK_FOOD = "\u0407\u0436\u0430";

  /** Ukrainian "apple". */
  private static final String UK_APPLE = "\u042f\u0431\u043b\u0443\u043a\u043e";

  /** Ukrainian "needle", starting with the letter I that precedes Yi. */
  private static final String UK_NEEDLE = "\u0418\u0433\u043b\u0430";

  private UUID accountId;
  private UUID categoryId;

  @BeforeEach
  void reset() {
    PrudentTest.reset();
    accountId = PrudentTest.seedAccount(PrudentTest.ALICE, "Wallet", "PLN");
    categoryId = PrudentTest.seedCategory(PrudentTest.ALICE, "Food");
  }

  private void seedRecord(String title, String payee, String note) {
    UUID id = PrudentTest.seedRecord(PrudentTest.ALICE, accountId, categoryId, -1_00L, "PLN");
    QuarkusTransaction.requiringNew()
        .run(
            () -> {
              RecordEntity r = RecordEntity.findById(id);
              r.title = title;
              r.payee = payee;
              r.note = note;
            });
  }

  private List<String> searchTitles(String search) throws Exception {
    Response response =
        PrudentTest.request(PrudentTest.JSON)
            .queryParam("search", search)
            .when()
            .get("/api/v1/records")
            .andReturn();
    assertEquals(200, response.statusCode());
    return PrudentTest.decode(PrudentTest.JSON, response, ListRecordsResponse.newBuilder())
        .build()
        .getRecordsList()
        .stream()
        .map(Record::getTitle)
        .sorted()
        .toList();
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void search_percentIsALiteralCharacter() throws Exception {
    seedRecord("Fee 50% off", null, null);
    seedRecord("Fee 500 off", null, null);
    assertEquals(List.of("Fee 50% off"), searchTitles("50%"));
    assertEquals(List.of("Fee 50% off"), searchTitles("%"));
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void search_underscoreAndBackslashAreLiteralCharacters() throws Exception {
    seedRecord("a_b", null, null);
    seedRecord("axb", null, null);
    seedRecord("c:\\tmp", null, null);
    seedRecord("c:/tmp", null, null);
    assertEquals(List.of("a_b"), searchTitles("a_b"));
    assertEquals(List.of("c:\\tmp"), searchTitles("\\"));
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void search_foldsCaseByTheFixedRuleInTitlePayeeAndNote() throws Exception {
    seedRecord("\u0141\u00d3D\u0179 trip", null, null);
    seedRecord("Train", "Biuro \u0141\u00d3D\u0179", null);
    seedRecord("Hotel", null, "w \u0142odzi i \u0142\u00f3d\u017a");
    seedRecord("Lodz", null, null);
    seedRecord(UK_FOOD, null, null);
    assertEquals(
        List.of("Hotel", "Train", "\u0141\u00d3D\u0179 trip"), searchTitles("\u0142\u00f3d\u017a"));
    assertEquals(List.of(UK_FOOD), searchTitles("\u0457\u0416\u0410"));
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void search_blankIsIgnoredAndTheTermIsTrimmed() throws Exception {
    seedRecord("One", null, null);
    seedRecord("Two", null, null);
    assertEquals(List.of("One", "Two"), searchTitles("   "));
    assertEquals(List.of("One"), searchTitles("  one "));
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void accountsAreListedInPinnedNameOrder() throws Exception {
    for (String name :
        new String[] {"Zupa", "\u0141azienka", "Lato", "bank", "Savings", UK_FOOD, UK_APPLE}) {
      PrudentTest.seedAccount(PrudentTest.ALICE, name, "PLN");
    }
    Response response =
        PrudentTest.request(PrudentTest.JSON).when().get("/api/v1/accounts").andReturn();
    List<String> names =
        PrudentTest.decode(PrudentTest.JSON, response, ListAccountsResponse.newBuilder())
            .build()
            .getAccountsList()
            .stream()
            .map(Account::getName)
            .toList();
    assertEquals(
        List.of("bank", "Lato", "\u0141azienka", "Savings", "Wallet", "Zupa", UK_FOOD, UK_APPLE),
        names);
  }

  /**
   * Names that differ only in case order upper case first by this rule. A database collation puts
   * lower case first (en_US) or every upper-case letter before every lower-case one (C), so this
   * is the case that tells the pinned rule from either.
   */
  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void namesThatDifferOnlyInCaseListUpperCaseFirst() throws Exception {
    for (String name : new String[] {"b", "B", "a", "A"}) {
      PrudentTest.seedAccount(PrudentTest.ALICE, name, "PLN");
    }
    Response response =
        PrudentTest.request(PrudentTest.JSON).when().get("/api/v1/accounts").andReturn();
    List<String> names =
        PrudentTest.decode(PrudentTest.JSON, response, ListAccountsResponse.newBuilder())
            .build()
            .getAccountsList()
            .stream()
            .map(Account::getName)
            .toList();
    assertEquals(List.of("A", "a", "B", "b", "Wallet"), names);
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void categoriesAreListedInPinnedNameOrder() throws Exception {
    for (String title :
        new String[] {
          "\u017bywno\u015b\u0107", "Zupa", "Cukier", "\u0106wiczenia", UK_APPLE, UK_FOOD, UK_NEEDLE
        }) {
      PrudentTest.seedCategory(PrudentTest.ALICE, title);
    }
    Response response =
        PrudentTest.request(PrudentTest.JSON).when().get("/api/v1/categories").andReturn();
    List<String> titles =
        PrudentTest.decode(PrudentTest.JSON, response, ListCategoriesResponse.newBuilder())
            .build()
            .getCategoriesList()
            .stream()
            .map(Category::getTitle)
            .toList();
    assertEquals(
        List.of(
            "Cukier",
            "\u0106wiczenia",
            "Food",
            "Zupa",
            "\u017bywno\u015b\u0107",
            UK_NEEDLE,
            UK_FOOD,
            UK_APPLE),
        titles);
  }

  @Test
  void freeMoneyListsContributingAccountsInPinnedNameOrder() {
    List<AccountEntity> accounts =
        List.of(
            account("\u0179r\u00f3d\u0142o"),
            account("Zupa"),
            account("\u0141azienka"),
            account("Lato"));
    FreeMoney.Position position =
        FreeMoney.calculate(accounts, Map.of(), List.of(), Map.of()).get("PLN");
    assertEquals(
        List.of("Lato", "\u0141azienka", "Zupa", "\u0179r\u00f3d\u0142o"),
        position.eligibleAccountIds().stream()
            .map(id -> accounts.stream().filter(a -> a.id.equals(id)).findFirst().orElseThrow().name)
            .toList());
  }

  private static AccountEntity account(String name) {
    AccountEntity a = new AccountEntity();
    a.id = UUID.randomUUID();
    a.userId = UUID.fromString(PrudentTest.ALICE);
    a.name = name;
    a.kind = AccountKind.CASH;
    a.isActive = true;
    a.eligibleForGoals = true;
    a.balances.add(new AccountBalance("PLN", 1_00L));
    return a;
  }
}
