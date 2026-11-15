package prudent;

import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.quarkus.test.junit.QuarkusTest;
import jakarta.inject.Inject;
import java.sql.Connection;
import java.sql.SQLException;
import java.sql.Statement;
import java.time.Instant;
import java.util.UUID;
import javax.sql.DataSource;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import prudent.imports.ImportState;

/** Migration coverage for V20261114120000 (ADR-092): every constraint, by name, on the owner connection. */
@QuarkusTest
class ImportCommitSchemaTest {

  @Inject DataSource dataSource;

  private UUID previewed;
  private UUID committed;

  @BeforeEach
  void seed() {
    PrudentTest.reset();
    previewed =
        PrudentTest.seedImportSession(
            PrudentTest.ALICE, ImportState.PREVIEWED, Instant.now().plusSeconds(3600));
    committed =
        PrudentTest.seedImportSession(
            PrudentTest.ALICE, ImportState.COMMITTED, Instant.now().plusSeconds(3600));
  }

  private void assertRefusedBy(String constraint, String sql) {
    SQLException refused =
        assertThrows(
            SQLException.class,
            () -> {
              try (Connection owner = dataSource.getConnection();
                  Statement statement = owner.createStatement()) {
                statement.executeUpdate(sql);
              }
            });
    assertTrue(refused.getMessage().contains(constraint), refused.getMessage());
  }

  @Test
  void onlyADuplicateRowCanBeIncluded() {
    assertRefusedBy(
        "prudent_import_row_include_only_duplicate",
        "UPDATE prudent_import_row SET include_duplicate = TRUE WHERE session_id = '" + previewed + "'");
  }

  @Test
  void aRejectedRowTakesNoDecision() {
    assertRefusedBy(
        "prudent_import_row_rejected_has_no_decision",
        "UPDATE prudent_import_row SET status = 'REJECTED', rejection_code = 'x.y',"
            + " category_id = '" + UUID.randomUUID() + "' WHERE session_id = '" + previewed + "'");
  }

  @Test
  void theCommitCountsTravelTogetherAreNotNegativeAndMarkExactlyACommit() {
    assertRefusedBy(
        "prudent_import_session_commit_counts_paired",
        "UPDATE prudent_import_session SET committed_already_imported = NULL WHERE id = '"
            + committed + "'");
    assertRefusedBy(
        "prudent_import_session_commit_counts_not_negative",
        "UPDATE prudent_import_session SET committed_written = -1 WHERE id = '" + committed + "'");
    assertRefusedBy(
        "prudent_import_session_commit_counts_iff_committed",
        "UPDATE prudent_import_session SET committed_written = NULL, committed_already_imported = NULL"
            + " WHERE id = '" + committed + "'");
    assertRefusedBy(
        "prudent_import_session_commit_counts_iff_committed",
        "UPDATE prudent_import_session SET committed_written = 1, committed_already_imported = 0"
            + " WHERE id = '" + previewed + "'");
  }

  @Test
  void aNoteIsAtMostFiveHundredCharacters_andAHintIsARuleCodeNeverOnARejectedRow() {
    assertRefusedBy(
        "prudent_import_row_note_length",
        "UPDATE prudent_import_row SET note = repeat('x', 501) WHERE session_id = '" + previewed + "'");
    assertRefusedBy(
        "prudent_import_row_hint_is_rule_code",
        "UPDATE prudent_import_row SET hint_code = 'Not A Rule' WHERE session_id = '" + previewed + "'");
    assertRefusedBy(
        "prudent_import_row_rejected_has_no_hint",
        "UPDATE prudent_import_row SET status = 'REJECTED', rejection_code = 'x.y',"
            + " hint_code = 'transfer.own_account' WHERE session_id = '" + previewed + "'");
  }

  @Test
  void defaultCategoriesExistOnlyWhileTheSessionIsOpen() {
    assertRefusedBy(
        "prudent_import_session_defaults_only_while_open",
        "UPDATE prudent_import_session SET default_expense_category_id = '" + UUID.randomUUID()
            + "' WHERE id = '" + committed + "'");
  }
}
