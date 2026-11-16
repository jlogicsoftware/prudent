package prudent.privacy;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.quarkus.narayana.jta.QuarkusTransaction;
import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.security.TestSecurity;
import io.restassured.response.Response;
import java.time.LocalDate;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import prudent.PrudentTest;
import prudent.proto.v1.DataExport;
import prudent.proto.v1.ExportImportKey;
import prudent.record.RecordEntity;

/**
 * The statement-import key (ADR-091) survives the export exactly, and only for the records a
 * statement import wrote (unit 10a, finding F-02): without it a statement imported before the data
 * moved would be written a second time after it.
 */
@QuarkusTest
class PrivacyImportKeysTest {

  /** Synthetic: the shape ADR-091 stores (scheme prefix, 64 lower-case hex), not a real digest. */
  private static final String FINGERPRINT_ONE = "v1:" + "ab".repeat(32);

  private static final String FINGERPRINT_TWO = "v1:" + "01".repeat(32);

  private UUID account;
  private UUID category;

  @BeforeEach
  void seed() {
    PrudentTest.reset();
    account = PrudentTest.seedAccount(PrudentTest.ALICE, "Main", "PLN");
    category = PrudentTest.seedCategory(PrudentTest.ALICE, "Food");
  }

  private UUID record(String fingerprint, Integer occurrence, String userId) {
    UUID id = UUID.randomUUID();
    QuarkusTransaction.requiringNew()
        .run(
            () -> {
              RecordEntity record = new RecordEntity();
              record.id = id;
              record.userId = UUID.fromString(userId);
              record.accountId = account;
              record.categoryId = category;
              record.title = "Row";
              record.amountMinor = -500;
              record.currency = "PLN";
              record.date = LocalDate.of(2026, 3, 10);
              record.importFingerprint = fingerprint;
              record.importOccurrence = occurrence;
              record.persist();
            });
    return id;
  }

  private DataExport export(String mode) throws Exception {
    Response response = PrudentTest.request(mode).when().get("/api/v1/privacy/export").andReturn();
    assertEquals(200, response.statusCode(), response.asString());
    return PrudentTest.decode(mode, response, DataExport.newBuilder()).build();
  }

  @ParameterizedTest
  @ValueSource(strings = {PrudentTest.JSON, PrudentTest.PROTOBUF})
  @TestSecurity(user = PrudentTest.ALICE)
  void anImportedRecordsKeyComesBackExactly(String mode) throws Exception {
    UUID first = record(FINGERPRINT_ONE, 1, PrudentTest.ALICE);
    // Two statement rows with one fingerprint: the occurrence is what tells them apart.
    UUID repeat = record(FINGERPRINT_ONE, 2, PrudentTest.ALICE);
    UUID other = record(FINGERPRINT_TWO, 1, PrudentTest.ALICE);

    DataExport data = export(mode);

    assertEquals(3, data.getRecordsCount());
    assertEquals(3, data.getRecordImportKeysCount());
    assertEquals(
        ExportImportKey.newBuilder()
            .setRecordId(first.toString())
            .setFingerprint(FINGERPRINT_ONE)
            .setOccurrence(1)
            .build(),
        key(data, first));
    assertEquals(2, key(data, repeat).getOccurrence());
    assertEquals(FINGERPRINT_ONE, key(data, repeat).getFingerprint());
    assertEquals(FINGERPRINT_TWO, key(data, other).getFingerprint());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void anOrdinaryRecordHasNoKeyAndNeitherDoesAnEmptyLedger() throws Exception {
    assertEquals(0, export(PrudentTest.JSON).getRecordImportKeysCount());

    UUID typed = record(null, null, PrudentTest.ALICE);
    UUID imported = record(FINGERPRINT_ONE, 1, PrudentTest.ALICE);

    DataExport data = export(PrudentTest.JSON);
    assertEquals(2, data.getRecordsCount());
    assertEquals(1, data.getRecordImportKeysCount());
    assertEquals(imported.toString(), data.getRecordImportKeys(0).getRecordId());
    assertTrue(
        data.getRecordImportKeysList().stream()
            .noneMatch(k -> k.getRecordId().equals(typed.toString())),
        "a record the person typed carries no key");
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void aNeighboursKeyIsNeverInThisExport() throws Exception {
    UUID bobsAccount = PrudentTest.seedAccount(PrudentTest.BOB, "Bob", "PLN");
    UUID mine = record(FINGERPRINT_ONE, 1, PrudentTest.ALICE);
    QuarkusTransaction.requiringNew()
        .run(
            () -> {
              RecordEntity theirs = new RecordEntity();
              theirs.id = UUID.randomUUID();
              theirs.userId = UUID.fromString(PrudentTest.BOB);
              theirs.accountId = bobsAccount;
              theirs.title = "Row";
              theirs.amountMinor = -500;
              theirs.currency = "PLN";
              theirs.date = LocalDate.of(2026, 3, 10);
              theirs.importFingerprint = FINGERPRINT_TWO;
              theirs.importOccurrence = 1;
              theirs.persist();
            });

    List<ExportImportKey> keys = export(PrudentTest.JSON).getRecordImportKeysList();

    assertEquals(1, keys.size());
    assertEquals(mine.toString(), keys.get(0).getRecordId());
  }

  private static ExportImportKey key(DataExport data, UUID record) {
    return data.getRecordImportKeysList().stream()
        .filter(k -> k.getRecordId().equals(record.toString()))
        .findFirst()
        .orElseThrow(() -> new AssertionError("no key exported for record " + record));
  }
}
