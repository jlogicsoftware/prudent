package prudent.parity;

import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.text.Normalizer;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Base64;
import java.util.HexFormat;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Objects;
import java.util.UUID;
import java.util.function.Supplier;
import prudent.imports.ErsteStatementImporter;
import prudent.imports.ImportRejectedException;
import prudent.imports.ImportRulesAccess;
import prudent.imports.ImportRulesAccess.Case;
import prudent.imports.ImportRulesAccess.Outcome;
import prudent.imports.ParsedRow;
import prudent.imports.ParsedStatement;
import prudent.imports.RowFingerprints;
import prudent.imports.RowKey;

/**
 * The golden vectors of unit 8a (Prudent Local's Erste parser and row fingerprints, {@code
 * docs/plans/PRUDENT-LOCAL-PLAN.md}): {@code erste_import.json} and {@code
 * import_fingerprints.json}, written by {@link GoldenVectorsTest}. Kept apart from that class only
 * for size; it writes nothing itself.
 *
 * <p><strong>The catalogue is checked before it is written.</strong> Every case of {@code
 * ImportFailureCatalogue} the parse stage decides is run through the server's code and the answer
 * is compared with what the catalogue says it must be; a disagreement throws here, so a golden file
 * can never carry an answer the server's own matrix would fail.
 *
 * <p>Statement bytes are written as base64. Two cases are too large for a file (a statement over
 * 5 MiB and one with more rows than an import holds); they are written as a recipe the Dart side
 * rebuilds, with the SHA-256 and length of the bytes, so the Dart side proves it rebuilt exactly
 * what the server read.
 *
 * <p>Non-ASCII test text is spelled with {@link #s} and code points, never as escapes in a string
 * literal, so that what the file holds is visible in a diff and no invisible character hides in the
 * source.
 */
final class ImportGoldenVectors {

  private ImportGoldenVectors() {}

  /** The destination account id the end-to-end fingerprints are computed for. */
  static final UUID ACCOUNT_ID = UUID.fromString("123e4567-e89b-42d3-a456-426614174000");

  private static final int INLINE_LIMIT = 64 * 1024;
  private static final String FORMAT_ID = "erste-pl-csv";

  /** Text from parts: a {@code String} as it is, an {@code Integer} as that code point. */
  static String s(Object... parts) {
    StringBuilder out = new StringBuilder();
    for (Object part : parts) {
      if (part instanceof Integer cp) {
        out.appendCodePoint(cp);
      } else {
        out.append((String) part);
      }
    }
    return out.toString();
  }

  /** A lone UTF-16 unit, which {@link #s} cannot spell (a surrogate is not a code point). */
  private static String unit(int unit) {
    return String.valueOf((char) unit);
  }

  // --- erste_import.json -------------------------------------------------------------------------

  static Map<String, Object> ersteImport() throws IOException {
    Map<String, Object> out = new LinkedHashMap<>();
    out.put("today", ImportRulesAccess.TODAY.toString());
    out.put("fingerprintAccountId", ACCOUNT_ID.toString());
    Map<String, Object> limits = new LinkedHashMap<>();
    limits.put("maxContentBytes", ImportRulesAccess.maxContentBytes());
    limits.put("maxRows", ImportRulesAccess.maxRows());
    limits.put("maxFieldChars", ImportRulesAccess.maxFieldChars());
    limits.put("maxReportedRows", ImportRulesAccess.maxReportedRows());
    out.put("limits", limits);
    out.put("ownTransferDescription", ErsteStatementImporter.OWN_TRANSFER_DESCRIPTION);
    out.put("hintOwnAccountTransfer", ParsedRow.HINT_OWN_ACCOUNT_TRANSFER);
    out.put("ruleShape", ImportRejectedException.RULE.pattern());
    out.put("emittedRules", new ArrayList<Object>(ImportRulesAccess.emittedRules()));
    out.put("coveredElsewhere", new LinkedHashMap<String, Object>(ImportRulesAccess.coveredElsewhere()));
    out.put("workflowCases", new ArrayList<Object>(ImportRulesAccess.workflowCases()));
    // Character.isDigit over every UTF-16 unit: the header test reads String.chars(), units.
    List<Object> digits = new ArrayList<>();
    int start = -1;
    for (int unit = 0; unit <= 0x10000; unit++) {
      boolean in = unit <= 0xFFFF && Character.isDigit((char) unit);
      if (in && start < 0) {
        start = unit;
      } else if (!in && start >= 0) {
        digits.add(List.of(start, unit - 1));
        start = -1;
      }
    }
    out.put("isDigitUnits", digits);

    List<Object> cases = new ArrayList<>();
    for (Case c : ImportRulesAccess.catalogue()) {
      Outcome outcome =
          ImportRulesAccess.parseStage(
              c.content(), ImportRulesAccess.TODAY, c.checkDestination(), c.destinationNumber());
      requireCatalogueAnswer(c, outcome);
      cases.add(
          entry(
              "catalogue", c.name(), c.content(), ImportRulesAccess.TODAY, c.checkDestination(),
              c.destinationNumber(), outcome));
    }
    for (String fixture :
        List.of("statement-minimal.csv", "statement-representative.csv", "statement-diacritics.csv")) {
      byte[] content = resource("/import/erste/" + fixture);
      Outcome outcome = ImportRulesAccess.parseStage(content, ImportRulesAccess.TODAY, false, null);
      if (outcome.rejection() != null) {
        throw new IllegalStateException("the synthetic fixture " + fixture + " no longer parses");
      }
      cases.add(entry("fixture", fixture, content, ImportRulesAccess.TODAY, false, null, outcome));
    }
    for (Object[] extra : extras()) {
      byte[] content = (byte[]) extra[1];
      LocalDate today = (LocalDate) extra[2];
      Outcome outcome = ImportRulesAccess.parseStage(content, today, true, ImportRulesAccess.ACCOUNT);
      cases.add(entry("extra", (String) extra[0], content, today, true, ImportRulesAccess.ACCOUNT, outcome));
    }
    out.put("cases", cases);
    out.put("destinations", destinations());
    out.put("stableIdentifiers", stableIdentifiers());
    return out;
  }

  /**
   * Statements that sit where Java's string and regex semantics differ from Dart's, and at the
   * edges of the date range: each name says what it probes. All synthetic (ADR-088).
   */
  private static List<Object[]> extras() {
    LocalDate today = ImportRulesAccess.TODAY;
    LocalDate leapDay = LocalDate.of(2028, 2, 29);
    String card = ImportRulesAccess.baseField(1, 2);
    String blik = ImportRulesAccess.baseField(2, 2);
    List<Object[]> out = new ArrayList<>();
    for (int cp : new int[] {0x85, 0x2028, 0x2029, 0x0B, 0x0C, 0x1C, 0xA0}) {
      out.add(x("a card merchant holding U+" + hex(cp), ImportRulesAccess.withField(1, 2, card.replace("SKLEP A", s("SKLEP", cp, "A"))), today));
    }
    for (int cp : new int[] {0xA0, 0x3000, 0xFEFF, 0x0B, 0x0C, 0x1C, 0x85, 0x2007}) {
      out.add(x("a card merchant starting with U+" + hex(cp), ImportRulesAccess.withField(1, 2, card.replace("PLN SKLEP A", s("PLN ", cp, "SKLEP A"))), today));
      out.add(x("a BLIK merchant starting with U+" + hex(cp), ImportRulesAccess.withField(2, 2, blik.replace("BLIK SKLEP", s("BLIK ", cp, "SKLEP"))), today));
    }
    out.add(x("a BLIK merchant holding U+0085", ImportRulesAccess.withField(2, 2, blik.replace("SKLEP B", s("SKLEP", 0x85, "B"))), today));
    for (int cp : new int[] {0xA0, 0x2003, 0xFEFF, 0x85, 0x1C, 0x2007, 0x202F, 0x200B, 0x3000, 0x0B}) {
      out.add(x("a BLIK counterparty of only U+" + hex(cp), ImportRulesAccess.withField(2, 3, s(cp)), today));
    }
    out.add(x("a BLIK counterparty account with no-break spaces", ImportRulesAccess.withField(2, 4, s("00", 0xA0, "0000 0000 0000 0000 0000 0010")), today));
    out.add(x("a BLIK counterparty account with a tab", ImportRulesAccess.withField(2, 4, "00\t0000 0000 0000 0000 0000 0010"), today));
    for (int cp : new int[] {0x0661, 0xFF11, 0xB2, 0x0966, 0x1D7CE}) {
      out.add(x("a summary's first field of U+" + hex(cp), ImportRulesAccess.withField(0, 0, s(cp, cp)), today));
    }
    out.add(x("a summary account with a no-break space", ImportRulesAccess.withField(0, 2, s("'00", 0xA0, "0000 0000 0000 0000 0000 0000 0001")), today));
    out.add(x("a summary account with PL", ImportRulesAccess.withField(0, 2, "'PL00 0000 0000 0000 0000 0000 0001"), today));
    out.add(x("a summary account in lower-case pl", ImportRulesAccess.withField(0, 2, "'pl00 0000 0000 0000 0000 0000 0001"), today));
    out.add(x("a summary account with a byte-order mark", ImportRulesAccess.withField(0, 2, s("'", 0xFEFF, "00 0000 0000 0000 0000 0000 0001")), today));
    out.add(x("a summary account of another number", ImportRulesAccess.withField(0, 2, "'00 0000 0000 0000 0000 0000 0009"), today));
    out.add(x("a summary account of letters", ImportRulesAccess.withField(0, 2, "'ab00 0000 0000 0000 0000 0000 0001"), today));
    out.add(x("a transaction a year from today", ImportRulesAccess.withDates(5, "16-11-2027", "16-11-2027"), today));
    out.add(x("a transaction a year and a day from today", ImportRulesAccess.withDates(5, "17-11-2027", "17-11-2027"), today));
    out.add(x("the first day of 2000", ImportRulesAccess.withDates(5, "01-01-2000", "01-01-2000"), today));
    out.add(x("on a leap day, a transaction on the 28th of February a year on", ImportRulesAccess.withDates(5, "28-02-2029", "28-02-2029"), leapDay));
    out.add(x("on a leap day, a transaction on the 1st of March a year on", ImportRulesAccess.withDates(5, "01-03-2029", "01-03-2029"), leapDay));
    out.add(x("a leap day in 2028", ImportRulesAccess.withDates(5, "29-02-2028", "29-02-2028"), leapDay));
    out.add(x("a leap day in 2100, which is not one", ImportRulesAccess.withDates(5, "29-02-2100", "29-02-2100"), today));
    out.add(x("a leap day in 2000", ImportRulesAccess.withDates(5, "29-02-2000", "29-02-2000"), today));
    out.add(x("an export date in a leap year's February", ImportRulesAccess.withField(0, 0, "2024-02-29"), today));
    out.add(x("an export date of year zero", ImportRulesAccess.withField(0, 0, "0000-01-01"), today));
    out.add(x("a BLIK amount of eleven digits", ImportRulesAccess.withField(2, 5, "-99999999999,99"), today));
    out.add(x("a BLIK amount of a thousand", ImportRulesAccess.withField(2, 5, "-1000,00"), today));
    out.add(x("a BLIK amount of one grosz", ImportRulesAccess.withField(2, 5, "-0,01"), today));
    out.add(x("a card payment of a thousand and more", cardOf("1234.56", "-1234,56"), today));
    out.add(x("a card payment whose text has a leading zero", cardOf("01.00", "-1,00"), today));
    out.add(x("a card payment of eleven digits", cardOf("99999999999.99", "-99999999999,99"), today));
    out.add(x("a sequence number of eighteen digits", ImportRulesAccess.withField(2, 7, "999999999999999999"), today));
    out.add(x("a sequence number of zero", ImportRulesAccess.withField(2, 7, "0"), today));
    out.add(x("a card merchant with a decomposed letter", ImportRulesAccess.withField(1, 2, card.replace("SKLEP A", s("SKLEP A", 0x328))), today));
    out.add(x("an own-account transfer in NFD (unchanged: its letters do not decompose)", ImportRulesAccess.withField(3, 2, Normalizer.normalize(ErsteStatementImporter.OWN_TRANSFER_DESCRIPTION, Normalizer.Form.NFD)), today));
    out.add(x("an own-account transfer with a decomposed acute in a merchant-like wording", ImportRulesAccess.withField(3, 2, s("Przelew na rachunek w", 0x142, "asny", 0x301)), today));
    out.add(x("an astral character in a BLIK merchant", ImportRulesAccess.withField(2, 2, blik.replace("SKLEP B", s("SKLEP ", 0x1F600))), today));
    out.add(x("a summary holder with a tab and a comma", ImportRulesAccess.withField(0, 3, "JAN\tTESTOWY, UL."), today));
    out.add(x("an outgoing own-account transfer to the same account", ImportRulesAccess.withField(3, 4, "00 0000 0000 0000 0000 0000 0001"), today));
    return out;
  }

  private static String hex(int cp) {
    return String.format("%04X", cp);
  }

  private static byte[] cardOf(String embedded, String amount) {
    String card = ImportRulesAccess.baseField(1, 2).replace("7.10", embedded);
    byte[] once = ImportRulesAccess.withField(1, 2, card);
    String text = new String(once, StandardCharsets.UTF_8);
    return text.replace("\"-7,10\"", "\"" + amount + "\"").getBytes(StandardCharsets.UTF_8);
  }

  private static Object[] x(String name, byte[] content, LocalDate today) {
    return new Object[] {name, content, today};
  }

  /** The catalogue's own expectation, checked against the server's answer before anything is written. */
  private static void requireCatalogueAnswer(Case c, Outcome outcome) {
    if (c.expectedCodes() != null) {
      if (outcome.rejection() != null) {
        throw new IllegalStateException(c.name() + ": refused as " + outcome.rejection().rule());
      }
      List<String> codes =
          outcome.statement().rows().stream().map(ParsedRow::rejectionCode).toList();
      if (!codes.equals(c.expectedCodes())) {
        throw new IllegalStateException(c.name() + ": flagged " + codes + ", not " + c.expectedCodes());
      }
      return;
    }
    ImportRejectedException rejection = outcome.rejection();
    if (rejection == null
        || !rejection.rule().equals(c.expectedRule())
        || !rejection.rowNumbers().equals(c.expectedRows())
        || rejection.totalRows() != c.expectedTotal()) {
      throw new IllegalStateException(c.name() + ": the parse stage does not answer as the catalogue says");
    }
  }

  private static Map<String, Object> entry(
      String source, String name, byte[] content, LocalDate today, boolean checkDestination,
      String destination, Outcome outcome) {
    Map<String, Object> entry = new LinkedHashMap<>();
    entry.put("source", source);
    entry.put("name", name);
    entry.put("today", today.toString());
    entry.put("checkDestination", checkDestination);
    entry.put("destination", destination);
    entry.put("content", content(name, content));
    entry.put("outcome", outcome(outcome));
    return entry;
  }

  private static Object content(String name, byte[] content) {
    if (content.length <= INLINE_LIMIT) {
      return Base64.getEncoder().encodeToString(content);
    }
    Map<String, Object> recipe = new LinkedHashMap<>();
    if (Arrays.equals(content, ImportRulesAccess.manyCards(ImportRulesAccess.maxRows() + 1))) {
      recipe.put("recipe", "manyCards");
      recipe.put("count", ImportRulesAccess.maxRows() + 1);
    } else if (allEqual(content)) {
      recipe.put("recipe", "repeat");
      recipe.put("byte", content[0] & 0xFF);
      recipe.put("count", content.length);
    } else {
      throw new IllegalStateException(name + ": too large to inline and no recipe rebuilds it");
    }
    recipe.put("length", content.length);
    recipe.put("sha256", sha256(content));
    return recipe;
  }

  private static boolean allEqual(byte[] content) {
    for (byte b : content) {
      if (b != content[0]) {
        return false;
      }
    }
    return true;
  }

  private static Map<String, Object> outcome(Outcome outcome) {
    Map<String, Object> out = new LinkedHashMap<>();
    if (outcome.rejection() != null) {
      out.put("rule", outcome.rejection().rule());
      out.put("rows", new ArrayList<Object>(outcome.rejection().rowNumbers()));
      out.put("total", outcome.rejection().totalRows());
      return out;
    }
    ParsedStatement statement = outcome.statement();
    out.put("currency", statement.currency());
    out.put("identity", statement.accountIdentity());
    List<Object> rows = new ArrayList<>();
    List<String> fingerprints = new ArrayList<>();
    for (ParsedRow row : statement.rows()) {
      Map<String, Object> r = new LinkedHashMap<>();
      r.put("row", row.rowNumber());
      if (row.isRejected()) {
        r.put("rejection", row.rejectionCode());
      } else {
        r.put("date", row.transactionDate().toString());
        r.put("booking", row.bookingDate() == null ? null : row.bookingDate().toString());
        r.put("amount", row.amountMinor());
        r.put("description", row.description());
        r.put("counterparty", row.counterparty());
        r.put("counterpartyAccount", row.counterpartyAccount());
        r.put("externalId", row.externalId());
        r.put("hint", row.hintCode());
        String fingerprint = fingerprint(row);
        r.put("fingerprint", fingerprint);
        fingerprints.add(fingerprint);
      }
      rows.add(r);
    }
    out.put("rows", rows);
    out.put("keys", keys(RowFingerprints.keys(fingerprints)));
    return out;
  }

  private static String fingerprint(ParsedRow row) {
    return RowFingerprints.fingerprint(
        ACCOUNT_ID,
        FORMAT_ID,
        "PLN",
        new RowFingerprints.Fields(
            row.transactionDate(),
            row.amountMinor(),
            row.description(),
            row.counterparty(),
            row.counterpartyAccount()));
  }

  private static List<Object> keys(List<RowKey> keys) {
    List<Object> out = new ArrayList<>();
    for (RowKey key : keys) {
      out.add(List.of(key.fingerprint(), key.occurrence()));
    }
    return out;
  }

  /** checkDestination over every pair of a statement identity and a stored number. */
  private static List<Object> destinations() {
    List<String> statementNumbers =
        Arrays.asList(null, ImportRulesAccess.ACCOUNT, "PL" + ImportRulesAccess.ACCOUNT);
    List<String> stored =
        Arrays.asList(
            null, "", " ", s(0xA0), s(0x2003), s(0xFEFF), ImportRulesAccess.ACCOUNT,
            "PL" + ImportRulesAccess.ACCOUNT, "pl " + ImportRulesAccess.ACCOUNT,
            ImportRulesAccess.OTHER_ACCOUNT);
    List<Object> out = new ArrayList<>();
    for (String statement : statementNumbers) {
      String identity = statement == null ? null : ParsedStatement.identityOf(statement);
      for (String number : stored) {
        Map<String, Object> entry = new LinkedHashMap<>();
        entry.put("identity", identity);
        entry.put("stored", number);
        try {
          ImportRejectedException rejected = ImportRulesAccess.checkDestination(identity, number);
          entry.put("rule", rejected == null ? null : rejected.rule());
        } catch (IllegalArgumentException unusable) {
          // A stored number that is not blank to Java but has nothing left once white space is
          // removed (a lone no-break space): identityOf refuses it. The account forms never store
          // one (AccountNumbers.normalize), so this is the method's answer, not a user's.
          entry.put("error", unusable.getClass().getSimpleName());
        }
        out.add(entry);
      }
    }
    return out;
  }

  /**
   * ParsedStatements.validate for a format that declares a stable identifier (none does today):
   * the identifier rules ADR-091 keeps ready for one.
   */
  private static List<Object> stableIdentifiers() {
    List<List<String>> lists =
        Arrays.asList(
            Arrays.asList("A1", "A2"),
            Arrays.asList("A1", null),
            Arrays.asList("A1", " "),
            Arrays.asList("A1", s(0x2003)),
            Arrays.asList("A1", s(0xA0)),
            Arrays.asList("A1", " A1 "),
            Arrays.asList("A1", s("A1", 0xA0)),
            Arrays.asList("A1", s("A1", 0x2003)),
            Arrays.asList("A1", "a1"),
            Arrays.asList(null, "A1"),
            Arrays.asList("A1", "A1", "A1"));
    List<Object> out = new ArrayList<>();
    for (List<String> ids : lists) {
      List<ParsedRow> rows = new ArrayList<>();
      for (int i = 0; i < ids.size(); i++) {
        rows.add(
            ParsedRow.accepted(i + 1, LocalDate.of(2026, 3, 1), null, -100L, "TEST", null, null, ids.get(i)));
      }
      ImportRejectedException rejected =
          ImportRulesAccess.validateStable(new ParsedStatement("PLN", rows, null));
      Map<String, Object> entry = new LinkedHashMap<>();
      entry.put("externalIds", new ArrayList<Object>(ids));
      entry.put("rule", rejected == null ? null : rejected.rule());
      entry.put("rows", rejected == null ? List.of() : new ArrayList<Object>(rejected.rowNumbers()));
      out.add(entry);
    }
    return out;
  }

  private static byte[] resource(String path) throws IOException {
    try (InputStream in = ImportGoldenVectors.class.getResourceAsStream(path)) {
      return Objects.requireNonNull(in, path).readAllBytes();
    }
  }

  // --- import_fingerprints.json ------------------------------------------------------------------

  static Map<String, Object> importFingerprints() {
    Map<String, Object> out = new LinkedHashMap<>();
    out.put("fingerprintPrefix", RowFingerprints.FINGERPRINT_PREFIX);
    out.put("stableIdPrefix", RowFingerprints.STABLE_ID_PREFIX);
    out.put("keyShape", RowFingerprints.KEY_SHAPE);

    // String.toUpperCase(Locale.ROOT) of every code point it changes. Root upper-casing has no
    // context, so this table is the whole of it.
    List<Object> upper = new ArrayList<>();
    for (int cp = 0; cp <= Character.MAX_CODE_POINT; cp++) {
      if (cp >= 0xD800 && cp <= 0xDFFF) {
        continue;
      }
      String text = Character.toString(cp);
      String upperCased = text.toUpperCase(Locale.ROOT);
      if (!upperCased.equals(text)) {
        upper.add(List.of(cp, upperCased));
      }
    }
    out.put("rootUpperCase", upper);

    // Every code point with a canonical decomposition, except the Hangul syllables (algorithmic,
    // and checked whole below): [cp, NFD, NFC(cp)]. NFC(NFD(cp)) is NFC(cp) by definition, so the
    // Dart side checks its composition with the second column and its decomposition with the first.
    List<Object> decompositions = new ArrayList<>();
    for (int cp = 0; cp <= Character.MAX_CODE_POINT; cp++) {
      if ((cp >= 0xD800 && cp <= 0xDFFF) || isHangulSyllable(cp)) {
        continue;
      }
      String text = Character.toString(cp);
      String nfd = Normalizer.normalize(text, Normalizer.Form.NFD);
      if (!nfd.equals(text)) {
        decompositions.add(List.of(cp, nfd, Normalizer.normalize(text, Normalizer.Form.NFC)));
      }
    }
    out.put("canonicalDecompositions", decompositions);
    for (int cp = 0xAC00; cp <= 0xD7A3; cp++) {
      String text = Character.toString(cp);
      String nfd = Normalizer.normalize(text, Normalizer.Form.NFD);
      if (!nfd.equals(hangulDecomposition(cp))
          || !Normalizer.normalize(nfd, Normalizer.Form.NFC).equals(text)) {
        throw new IllegalStateException("the JDK no longer decomposes Hangul syllables algorithmically");
      }
    }
    out.put("hangulSyllablesAlgorithmic", true);

    List<Object> normalise = new ArrayList<>();
    for (String input : normaliseInputs()) {
      Map<String, Object> entry = new LinkedHashMap<>();
      entry.put("input", input);
      entry.put("normalise", RowFingerprints.normalise(input));
      normalise.add(entry);
    }
    out.put("normalise", normalise);

    List<Object> fingerprints = new ArrayList<>();
    List<String> accounts =
        List.of("123e4567-e89b-42d3-a456-426614174000", "00000000-0000-0000-0000-000000000000");
    long[] amounts = {-710L, 1L, 10_000L, -9_999_999_999_999L, Long.MAX_VALUE, Long.MIN_VALUE};
    String[] dates = {"2026-03-10", "2000-01-01", "2027-11-16"};
    int i = 0;
    for (String account : accounts) {
      for (long amount : amounts) {
        for (String date : dates) {
          String description = textAt(i);
          String counterparty = textAt(i + 7);
          String counterpartyAccount = i % 3 == 0 ? null : "0000000000000000000000001" + (i % 10);
          fingerprints.add(
              fingerprintCase(account, FORMAT_ID, "PLN", date, amount, description, counterparty, counterpartyAccount));
          i++;
        }
      }
    }
    for (String text : normaliseInputs()) {
      fingerprints.add(fingerprintCase(accounts.get(0), FORMAT_ID, "PLN", "2026-03-10", -100L, text, text, text));
    }
    // Length prefixes: moving characters between fields changes the fingerprint.
    fingerprints.add(fingerprintCase(accounts.get(0), FORMAT_ID, "PLN", "2026-03-10", -100L, "AB", "C", null));
    fingerprints.add(fingerprintCase(accounts.get(0), FORMAT_ID, "PLN", "2026-03-10", -100L, "A", "BC", null));
    fingerprints.add(fingerprintCase(accounts.get(0), "another-format", "EUR", "2026-03-10", -100L, "A", "BC", null));
    out.put("fingerprints", fingerprints);

    List<Object> stable = new ArrayList<>();
    for (String externalId :
        Arrays.asList(null, "", " ", s(0x2003), s(0xA0), "1", " 1 ", s("1", 0xA0), s(0x85, "1"), s("abc") + unit(0xD800))) {
      Map<String, Object> entry = new LinkedHashMap<>();
      entry.put("accountId", accounts.get(0));
      entry.put("formatId", FORMAT_ID);
      entry.put("externalId", externalId);
      entry.put(
          "key",
          attempt(
              () -> {
                RowKey key = RowFingerprints.stableIdKey(UUID.fromString(accounts.get(0)), FORMAT_ID, externalId);
                return key.fingerprint() + "#" + key.occurrence();
              }));
      stable.add(entry);
    }
    out.put("stableIdKeys", stable);

    List<Object> keyLists = new ArrayList<>();
    String a = "v1:" + "a".repeat(64);
    String b = "v1:" + "b".repeat(64);
    String c = "v1:" + "c".repeat(64);
    for (List<String> list :
        List.of(List.<String>of(), List.of(a), List.of(a, a, a), List.of(a, b, a, c, b, a))) {
      Map<String, Object> entry = new LinkedHashMap<>();
      entry.put("fingerprints", new ArrayList<Object>(list));
      entry.put("keys", keys(RowFingerprints.keys(list)));
      keyLists.add(entry);
    }
    out.put("keys", keyLists);
    return out;
  }

  private static String textAt(int i) {
    List<String> inputs = normaliseInputs();
    return inputs.get(i % inputs.size());
  }

  private static Map<String, Object> fingerprintCase(
      String account, String formatId, String currency, String date, long amount,
      String description, String counterparty, String counterpartyAccount) {
    Map<String, Object> entry = new LinkedHashMap<>();
    entry.put("accountId", account);
    entry.put("formatId", formatId);
    entry.put("currency", currency);
    entry.put("date", date);
    entry.put("amount", amount);
    entry.put("description", description);
    entry.put("counterparty", counterparty);
    entry.put("counterpartyAccount", counterpartyAccount);
    entry.put(
        "fingerprint",
        RowFingerprints.fingerprint(
            UUID.fromString(account),
            formatId,
            currency,
            new RowFingerprints.Fields(
                LocalDate.parse(date), amount, description, counterparty, counterpartyAccount)));
    return entry;
  }

  /** The general hostile text, and text that probes NFC, white space runs and root upper-casing. */
  private static List<String> normaliseInputs() {
    List<String> inputs = new ArrayList<>(HostileText.general());
    inputs.addAll(
        Arrays.asList(
            "Zakup BLIK SKLEP B TESTOWY ref:00000000001",
            s("DOP. MC 000000******0000 P", 0x141, "ATNO", 0x15A, 0x106, " KART", 0x104, " 7.10 PLN SKLEP A TESTOWY"),
            ErsteStatementImporter.OWN_TRANSFER_DESCRIPTION,
            s("przelew  na", 0xA0, "rachunek", 0x2003, "w", 0x142, "asny"),
            s("sklep a", 0x328),
            s("sklep ", 0x105),
            s("e", 0x301, 0x327),
            s("e", 0x327, 0x301),
            s("a", 0x308, 0x301, 0x323),
            s(0x1E9B, 0x323),
            s(0x212B),
            s(0x2126),
            s(0x344),
            s(0xF73),
            s(0x1100, 0x1161, 0x11A8),
            s(0xAC00, 0x11A8),
            s(0xD55C, 0xAD6D, 0xC5B4),
            s(0x149),
            s(0x390),
            s(0x1FB3),
            s(0x1F80),
            s(0x345),
            s("a", 0x345),
            s(0x1C5),
            s(0x1F0),
            s(0xFB13),
            s(0x1E96),
            s(0xAB70),
            s(0x282),
            s(0x10428),
            s(0x1E922),
            s(0x10D0),
            s(0x1F0, 0x323),
            s("a", 0x85, "b", 0x2028, "c", 0x2029, "d"),
            s("a", 0x0B, 0x0C, 0x1C, "b"),
            s("a", 0x180E, "b"),
            s("a", 0x200B, "b"),
            s(0xA0, 0xA0, "a", 0xA0, 0xA0),
            "\ta\t\tb\t",
            s(0xFEFF, " a ", 0xFEFF),
            s(0x1F600, " ", 0x1F600),
            // U+D7A4, just past the last Hangul syllable: unorm_dart 0.3.3 takes it for one.
            s(0xD7A4),
            s(0xD7A4, 0x11A8),
            s(0xD7A3, 0x11A8),
            s(0xD788, 0x11A8),
            s("e", 0x301, 0xD7A4, 0x301, "e", 0x301)));
    return inputs;
  }

  private static boolean isHangulSyllable(int cp) {
    return cp >= 0xAC00 && cp <= 0xD7A3;
  }

  private static String hangulDecomposition(int cp) {
    int index = cp - 0xAC00;
    int leading = 0x1100 + index / (21 * 28);
    int vowel = 0x1161 + (index % (21 * 28)) / 28;
    int trailing = index % 28;
    StringBuilder out = new StringBuilder().appendCodePoint(leading).appendCodePoint(vowel);
    if (trailing != 0) {
      out.appendCodePoint(0x11A7 + trailing);
    }
    return out.toString();
  }

  private static Map<String, Object> attempt(Supplier<String> rule) {
    Map<String, Object> result = new LinkedHashMap<>();
    try {
      result.put("ok", rule.get());
    } catch (RuntimeException failed) {
      result.put("error", failed.getClass().getSimpleName());
    }
    return result;
  }

  private static String sha256(byte[] content) {
    try {
      return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(content));
    } catch (NoSuchAlgorithmException missing) {
      throw new IllegalStateException(missing);
    }
  }
}
