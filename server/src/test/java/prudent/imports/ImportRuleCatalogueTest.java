package prudent.imports;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Set;
import java.util.TreeSet;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Collectors;
import java.util.stream.Stream;
import org.junit.jupiter.api.Test;

/**
 * Holds the rules the import code can emit against the rules a test proves (M6, jlogicsoftware/
 * prudent#77, ADR-094). The set of emitted rules is read from the sources of {@code prudent.imports},
 * every dotted lower-case string literal in them, the way the client's {@code import_failure_test}
 * reads it; the proven set is {@link ImportFailureCatalogue}'s cases plus the few rules another stage
 * owns, each named with the test that proves it. A rule added without a case fails here, and so does
 * a case for a rule that no longer exists, so the catalogue cannot drift in either direction.
 */
class ImportRuleCatalogueTest {

  private static final Path SOURCES = Path.of("src/main/java/prudent/imports");
  private static final Path TESTS = Path.of("src/test/java/prudent/imports");

  private static final Pattern LITERAL = Pattern.compile("\"([^\"\\\\\\n]*)\"");
  private static final Pattern CODE = Pattern.compile("[a-z][a-z0-9_]*(\\.[a-z][a-z0-9_]*)+");
  /** Dotted literals that are another library's keys, not rules. */
  private static final Set<String> NOT_RULES_PREFIXES = Set.of("jakarta.", "java.", "javax.", "org.", "com.", "prudent.");

  /** Every rule-shaped string literal in the import package's main sources, comments removed. */
  static Set<String> emittedRules() throws IOException {
    Set<String> rules = new TreeSet<>();
    try (Stream<Path> files = Files.walk(SOURCES)) {
      for (Path file : files.filter(f -> f.toString().endsWith(".java")).toList()) {
        String source =
            Files.readString(file, StandardCharsets.UTF_8)
                .replaceAll("(?s)/\\*.*?\\*/", "")
                .replaceAll("//[^\\n]*", "");
        Matcher literal = LITERAL.matcher(source);
        while (literal.find()) {
          String text = literal.group(1);
          if (CODE.matcher(text).matches() && NOT_RULES_PREFIXES.stream().noneMatch(text::startsWith)) {
            rules.add(text);
          }
        }
      }
    }
    return rules;
  }

  @Test
  void theScanSeesTheRulesTheImporterEmits() throws IOException {
    Set<String> emitted = emittedRules();
    assertTrue(emitted.contains("encoding.not_utf8"), emitted.toString());
    assertTrue(emitted.contains("commit.category_unavailable"), emitted.toString());
    assertFalse(emitted.contains("jakarta.persistence.lock.timeout"));
    assertTrue(emitted.size() > 30, emitted.toString());
  }

  @Test
  void everyRuleTheImportCanEmitHasACaseOrAnNamedTest() throws IOException {
    Set<String> proven = new TreeSet<>(ImportFailureCatalogue.coveredRules());
    proven.addAll(ImportFailureCatalogue.coveredElsewhere().keySet());

    Set<String> untested = new TreeSet<>(emittedRules());
    untested.removeAll(proven);
    assertEquals(
        Set.of(),
        untested,
        "these rules can be emitted and no failure case or named test proves them: add a case to"
            + " ImportFailureCatalogue (or a named test to coveredElsewhere)");
  }

  @Test
  void noCaseNamesARuleThatIsNoLongerEmitted() throws IOException {
    Set<String> stale = new TreeSet<>(ImportFailureCatalogue.coveredRules());
    stale.addAll(ImportFailureCatalogue.coveredElsewhere().keySet());
    stale.removeAll(emittedRules());
    assertEquals(Set.of(), stale, "these rules are in the catalogue and nothing emits them");
  }

  @Test
  void aRuleIsNotBothInTheMatrixAndMarkedAsCoveredElsewhere() {
    Set<String> both = new TreeSet<>(ImportFailureCatalogue.coveredRules());
    both.retainAll(ImportFailureCatalogue.coveredElsewhere().keySet());
    assertEquals(Set.of(), both);
  }

  @Test
  void everyNamedTestExists() throws IOException {
    for (var entry : ImportFailureCatalogue.coveredElsewhere().entrySet()) {
      String[] parts = entry.getValue().split("#");
      assertEquals(2, parts.length, entry.getValue());
      Path file = TESTS.resolve(parts[0] + ".java");
      assertTrue(Files.exists(file), entry.getKey() + ": no test class " + parts[0]);
      String source = Files.readString(file, StandardCharsets.UTF_8);
      Matcher method = Pattern.compile("void\\s+" + Pattern.quote(parts[1]) + "\\s*\\(").matcher(source);
      assertTrue(method.find(), entry.getKey() + ": " + parts[0] + " has no test method " + parts[1]);
      // The method's own text, up to the next annotated member, must mention the rule, so a method
      // cannot be renamed or emptied into unrelated work and keep the rule "covered".
      String rest = source.substring(method.end());
      Matcher next = Pattern.compile("\\n  @|\\n  (?:private |static )").matcher(rest);
      String body = next.find() ? rest.substring(0, next.start()) : rest;
      assertTrue(
          body.contains("\"" + entry.getKey() + "\"")
              || body.contains(entry.getKey())
              || body.contains(entry.getKey().replace('.', '_')),
          entry.getKey() + " is not mentioned in the body of " + parts[0] + "#" + parts[1]);
    }
  }

  @Test
  void theMatrixIsBroadEnoughToBeWorthTheName() {
    assertTrue(ImportFailureCatalogue.refusals().size() >= 170, "refusals: " + ImportFailureCatalogue.refusals().size());
    assertTrue(ImportFailureCatalogue.flagged().size() >= 38, "flagged: " + ImportFailureCatalogue.flagged().size());
    // Every case has a distinct name, so a failure names exactly one file.
    assertEquals(
        ImportFailureCatalogue.refusals().size(),
        ImportFailureCatalogue.refusals().stream().map(ImportFailureCatalogue.Refusal::name).collect(Collectors.toSet()).size());
    assertEquals(
        ImportFailureCatalogue.flagged().size(),
        ImportFailureCatalogue.flagged().stream().map(ImportFailureCatalogue.Flagged::name).collect(Collectors.toSet()).size());
  }
}
