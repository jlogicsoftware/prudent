package prudent;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;

import io.quarkus.narayana.jta.QuarkusTransaction;
import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.security.TestSecurity;
import io.restassured.response.Response;
import java.time.LocalDate;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import prudent.proto.v1.UpdateRecordRequest;
import prudent.record.RecordEntity;

/**
 * What editing or moving an imported record does to its statement-row key (ADR-091): an edit of
 * date, amount, text or category keeps it (it names the row the record came from, not its content),
 * a move to another account clears it (it names a row of THAT account).
 */
@QuarkusTest
@TestSecurity(user = PrudentTest.ALICE)
class RecordImportKeyTest {

  private static final String KEY = "v1:" + "d".repeat(64);

  private UUID accountA;
  private UUID accountB;
  private UUID category;

  @BeforeEach
  void seed() {
    PrudentTest.reset();
    accountA = PrudentTest.seedAccount(PrudentTest.ALICE, "A", "PLN");
    accountB = PrudentTest.seedAccount(PrudentTest.ALICE, "B", "PLN");
    category = PrudentTest.seedCategory(PrudentTest.ALICE, "Food");
  }

  private UUID importedRecord(UUID account) {
    UUID id = UUID.randomUUID();
    QuarkusTransaction.requiringNew()
        .run(
            () -> {
              RecordEntity record = new RecordEntity();
              record.id = id;
              record.userId = UUID.fromString(PrudentTest.ALICE);
              record.accountId = account;
              record.categoryId = category;
              record.title = "Imported";
              record.amountMinor = -500;
              record.currency = "PLN";
              record.date = LocalDate.of(2026, 3, 10);
              record.importFingerprint = KEY;
              record.importOccurrence = 1;
              record.persist();
            });
    return id;
  }

  private Response put(UUID record, UUID account, String title, long amount, String date)
      throws Exception {
    UpdateRecordRequest update =
        UpdateRecordRequest.newBuilder()
            .setTitle(title)
            .setAmountMinor(amount)
            .setDate(date)
            .setCategoryId(category.toString())
            .setAccountId(account.toString())
            .setCurrency("PLN")
            .build();
    return PrudentTest.body(
            PrudentTest.request(PrudentTest.JSON), PrudentTest.JSON, update)
        .when()
        .put("/api/v1/records/" + record)
        .andReturn();
  }

  private RecordEntity stored(UUID id) {
    return QuarkusTransaction.requiringNew().call(() -> RecordEntity.<RecordEntity>findById(id));
  }

  @Test
  void editingDateAmountAndTextKeepsTheKey() throws Exception {
    UUID record = importedRecord(accountA);

    Response response = put(record, accountA, "Renamed", -900, "2026-03-12");

    assertEquals(200, response.statusCode(), response.asString());
    RecordEntity after = stored(record);
    assertEquals(KEY, after.importFingerprint);
    assertEquals(1, after.importOccurrence);
    assertEquals(-900, after.amountMinor);
  }

  @Test
  void movingToAnotherAccountClearsTheKeyAndFreesTheOldSlot() throws Exception {
    UUID record = importedRecord(accountA);

    Response response = put(record, accountB, "Imported", -500, "2026-03-10");

    assertEquals(200, response.statusCode(), response.asString());
    RecordEntity after = stored(record);
    assertNull(after.importFingerprint);
    assertNull(after.importOccurrence);
    assertEquals(
        0,
        QuarkusTransaction.requiringNew()
            .call(
                () ->
                    RecordEntity.importedKeys(
                            UUID.fromString(PrudentTest.ALICE), accountA, java.util.List.of(KEY))
                        .size()));
  }

  @Test
  void movingARecordOntoAnAccountThatHoldsTheSameKeyIsNotAServerError() throws Exception {
    // Same key text in two accounts is legal (the key is per account). Moving one onto the other
    // used to collide on the unique index and answer 500.
    UUID inA = importedRecord(accountA);
    UUID inB = importedRecord(accountB);

    Response response = put(inB, accountA, "Imported", -500, "2026-03-10");

    assertEquals(200, response.statusCode(), response.asString());
    assertNull(stored(inB).importFingerprint);
    assertNotNull(stored(inA).importFingerprint);
  }
}
