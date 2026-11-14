package prudent.imports;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertSame;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.time.LocalDate;
import java.util.List;
import org.junit.jupiter.api.Test;
import prudent.error.PrudentException;

/** The importer registry (ADR-089): lookup by format id, and a broken registry fails at boot. */
class ImportFormatsTest {

  private static StatementImporter importer(String id) {
    return new StatementImporter() {
      @Override
      public String formatId() {
        return id;
      }

      @Override
      public ParsedStatement parse(byte[] content, ImportContext context) {
        throw new UnsupportedOperationException();
      }
    };
  }

  @Test
  void aKnownFormatResolvesToItsImporter() {
    StatementImporter a = importer("bank-a");
    ImportFormats formats = new ImportFormats(List.of(a, importer("bank-b")));
    assertSame(a, formats.require("bank-a"));
    assertEquals(List.of("bank-a", "bank-b"), formats.ids());
  }

  @Test
  void anUnknownFormatIsAnInvalidRequestThatListsWhatIsSupportedAndDoesNotEchoTheInput() {
    ImportFormats formats = new ImportFormats(List.of(importer("bank-a")));
    PrudentException refused =
        assertThrows(PrudentException.class, () -> formats.require("<script>x</script>"));
    assertEquals(PrudentException.INVALID, refused.code());
    assertEquals(400, refused.status().getStatusCode());
    assertTrue(refused.getMessage().contains("bank-a"));
    assertFalse(refused.getMessage().contains("script"));
    assertThrows(PrudentException.class, () -> formats.require(null));
    assertThrows(PrudentException.class, () -> formats.require(""));
  }

  @Test
  void aRegistryWithNoImportersRefusesEveryFormat() {
    PrudentException refused =
        assertThrows(
            PrudentException.class,
            () -> new ImportFormats(List.of()).require(ImportFormatIds.ERSTE_PL_CSV));
    assertTrue(refused.getMessage().contains("none"));
  }

  @Test
  void twoImportersClaimingOneIdFailTheBootInsteadOfPickingOne() {
    IllegalStateException failure =
        assertThrows(
            IllegalStateException.class,
            () -> new ImportFormats(List.of(importer("bank-a"), importer("bank-a"))));
    assertTrue(failure.getMessage().contains("bank-a"));
  }

  @Test
  void anIdThatIsNotAPlainIdentifierFailsTheBoot() {
    for (String bad : List.of("", "Bank", "bank a", "bank_a", "-bank")) {
      assertThrows(
          IllegalStateException.class, () -> new ImportFormats(List.of(importer(bad))), bad);
    }
  }

  @Test
  void aRejectionCarriesARuleAndARowNumberAndNothingElse() {
    ImportRejectedException rejected = new ImportRejectedException("date.invalid", 7);
    assertEquals("The statement was rejected at row 7 (date.invalid).", rejected.getMessage());
    assertThrows(
        IllegalArgumentException.class,
        () -> new ImportRejectedException("Jan Kowalski, ul. Testowa 1"));
    assertThrows(IllegalArgumentException.class, () -> new ImportRejectedException("a.b", 0));
  }

  @Test
  void aBrokenImporterResultIsRefusedByTheWorkflowsOwnChecks() {
    LocalDate day = LocalDate.of(2026, 11, 1);
    assertThrows(
        IllegalStateException.class,
        () -> ParsedStatements.validate("f", new ParsedStatement("PLN", List.of())));
    assertThrows(
        IllegalStateException.class,
        () ->
            ParsedStatements.validate(
                "f", new ParsedStatement("pln", List.of(ParsedRow.accepted(1, day, null, 5, "TEST", null, null, null)))));
    assertThrows(
        IllegalStateException.class,
        () ->
            ParsedStatements.validate(
                "f", new ParsedStatement("PLN", List.of(ParsedRow.accepted(1, day, null, 0, "TEST", null, null, null)))));
    assertThrows(
        IllegalStateException.class,
        () ->
            ParsedStatements.validate(
                "f",
                new ParsedStatement(
                    "PLN",
                    List.of(
                        ParsedRow.accepted(1, day, null, 5, "TEST", null, null, null),
                        ParsedRow.accepted(1, day, null, 6, "TEST", null, null, null)))));
    assertThrows(
        IllegalStateException.class,
        () ->
            ParsedStatements.validate(
                "f",
                new ParsedStatement(
                    "PLN", List.of(new ParsedRow(1, null, null, null, "TEST", null, null, null, "a.b")))));
    ParsedStatements.validate(
        "f",
        new ParsedStatement(
            "PLN",
            List.of(ParsedRow.accepted(1, day, null, -5, "TEST", null, null, null), ParsedRow.rejected(2, "amount.zero"))));
  }
}
