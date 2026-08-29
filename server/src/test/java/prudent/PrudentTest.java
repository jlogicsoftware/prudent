package prudent;

import static io.restassured.RestAssured.given;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.google.protobuf.InvalidProtocolBufferException;
import com.google.protobuf.Message;
import com.google.protobuf.util.JsonFormat;
import io.quarkus.narayana.jta.QuarkusTransaction;
import io.restassured.response.Response;
import io.restassured.specification.RequestSpecification;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.UUID;
import prudent.account.AccountBalance;
import prudent.account.AccountEntity;
import prudent.account.AccountKind;
import prudent.category.CategoryEntity;
import prudent.record.RecordEntity;
import prudent.settings.SettingsEntity;
import zen.identity.auth.SessionService;
import zen.identity.user.User;
import zen.identity.user.UserRole;

/**
 * Shared machinery for Prudent's {@code @QuarkusTest} suites: the two transport modes, the two test
 * identities, and a clean database per test.
 *
 * <p><strong>Why both transport modes run through one helper.</strong> The JSON and Protobuf paths
 * are genuinely different code — binary uses the generated descriptors, canonical proto3 JSON
 * resolves accessors reflectively — and jZen's own history records a revision that served Protobuf
 * perfectly and 500'd on every JSON response. A suite that exercises one mode proves half the
 * surface. Putting both behind {@link #send} makes running both the path of least resistance rather
 * than a discipline each test has to remember.
 */
public final class PrudentTest {

  public static final String TRANSPORT_HEADER = "X-Zen-Transport";
  public static final String JSON = "json";
  public static final String PROTOBUF = "protobuf";
  public static final String PROTOBUF_TYPE = "application/x-protobuf";

  /**
   * The two identities every ownership assertion uses. Fixed rather than random so a failure names
   * the same user twice and is greppable in a log.
   */
  public static final String ALICE = "aaaaaaaa-0000-0000-0000-00000000000a";

  public static final String BOB = "bbbbbbbb-0000-0000-0000-00000000000b";

  private PrudentTest() {}

  /**
   * Empties Prudent's tables and re-seeds the two users.
   *
   * <p>Order matters: records reference accounts and categories, and the migration deliberately
   * carries no {@code ON DELETE CASCADE} — deleting an account with records is refused by the
   * database exactly as it is refused by the resource.
   */
  public static void reset() {
    QuarkusTransaction.requiringNew()
        .run(
            () -> {
              RecordEntity.deleteAll();
              AccountEntity.deleteAll();
              CategoryEntity.deleteAll();
              SettingsEntity.deleteAll();
              User.deleteAll();
              persistUser(UUID.fromString(ALICE), "alice@example.com");
              persistUser(UUID.fromString(BOB), "bob@example.com");
            });
  }

  /**
   * A {@code users} row for a test identity.
   *
   * <p>{@code @TestSecurity} mints the {@code SecurityIdentity} on its own, but zen-identity's
   * {@code RoleAugmentor} reads the {@code users} table to load authority roles — it never trusts
   * the JWT for them — so an identity with no row behind it is not the shape production produces.
   */
  private static void persistUser(UUID id, String email) {
    User user = new User();
    user.id = id;
    user.email = email;
    user.displayName = email;
    user.role = UserRole.USER;
    user.language = "en";
    user.createdAt = OffsetDateTime.now();
    user.persist();
  }

  /**
   * Persists an account owned by {@code userId}, with the given currencies at zero.
   *
   * <p>Seeded directly rather than through the API because the suites that need it are asserting
   * something else — and because the ownership suite needs rows belonging to a user it is not
   * authenticated as, which no amount of API calling can produce.
   *
   * @return the new account's id
   */
  public static UUID seedAccount(String userId, String name, String... currencies) {
    UUID id = UUID.randomUUID();
    QuarkusTransaction.requiringNew()
        .run(
            () -> {
              AccountEntity account = new AccountEntity();
              account.id = id;
              account.userId = UUID.fromString(userId);
              account.name = name;
              account.kind = AccountKind.CASH;
              account.isActive = true;
              account.includeInTotal = true;
              account.includeInOverview = true;
              for (String currency : currencies) {
                account.balances.add(new AccountBalance(currency, 0L));
              }
              account.persist();
            });
    return id;
  }

  /** Persists a category owned by {@code userId}. */
  public static UUID seedCategory(String userId, String title) {
    UUID id = UUID.randomUUID();
    QuarkusTransaction.requiringNew()
        .run(
            () -> {
              CategoryEntity category = new CategoryEntity();
              category.id = id;
              category.userId = UUID.fromString(userId);
              category.title = title;
              category.iconKey = "food";
              category.description = "";
              category.colorArgb = 0xFF4CAF50L;
              category.persist();
            });
    return id;
  }

  /** Persists a settings row owned by {@code userId}. */
  public static void seedSettings(String userId, String mainCurrency) {
    QuarkusTransaction.requiringNew()
        .run(
            () -> {
              SettingsEntity settings = new SettingsEntity();
              settings.userId = UUID.fromString(userId);
              settings.mainCurrency = mainCurrency;
              settings.persist();
            });
  }

  /**
   * Reads a user's stored main currency straight from the database, bypassing the API.
   *
   * <p>Used to assert what a request did <em>not</em> touch. Going through the API would need a
   * second authenticated identity in one test, which {@code @TestSecurity} cannot provide — and the
   * question here is about the row, not about the endpoint.
   */
  public static String storedCurrency(String userId) {
    return QuarkusTransaction.requiringNew()
        .call(() -> SettingsEntity.<SettingsEntity>findById(UUID.fromString(userId)).mainCurrency);
  }

  /** Persists a record owned by {@code userId}, against an account and category it already owns. */
  public static UUID seedRecord(
      String userId, UUID accountId, UUID categoryId, long amountMinor, String currency) {
    return seedRecord(userId, accountId, categoryId, amountMinor, currency, LocalDate.of(2026, 8, 17));
  }

  /**
   * The same as {@link #seedRecord(String, UUID, UUID, long, String)}, with an explicit date — for
   * the analytics suite, which asserts against period BOUNDARIES rather than one fixed day.
   */
  public static UUID seedRecord(
      String userId, UUID accountId, UUID categoryId, long amountMinor, String currency, LocalDate date) {
    UUID id = UUID.randomUUID();
    QuarkusTransaction.requiringNew()
        .run(
            () -> {
              RecordEntity entity = new RecordEntity();
              entity.id = id;
              entity.userId = UUID.fromString(userId);
              entity.title = "Seeded";
              entity.amountMinor = amountMinor;
              entity.currency = currency;
              entity.date = date;
              entity.accountId = accountId;
              entity.categoryId = categoryId;
              entity.persist();
            });
    return id;
  }

  /**
   * A request in the named transport mode, carrying a matching CSRF double-submit pair.
   *
   * <p><strong>The CSRF pair is not test scaffolding, it is what a real client sends.</strong>
   * zen-identity's {@code CsrfFilter} refuses any mutating request whose {@code X-CSRF-Token} header
   * does not match its {@code XSRF-TOKEN} cookie, so a POST without the pair is 403 before a
   * resource method runs. It is attached to every request here rather than only to mutations
   * because a read that carries one is exactly as valid — and a helper that had to be chosen
   * correctly per verb is a helper someone will choose wrongly.
   */
  public static RequestSpecification request(String mode) {
    String csrf = UUID.randomUUID().toString();
    return given()
        .header(TRANSPORT_HEADER, mode)
        .contentType(PROTOBUF.equals(mode) ? PROTOBUF_TYPE : "application/json")
        .cookie(SessionService.CSRF_COOKIE, csrf)
        .header(SessionService.CSRF_HEADER, csrf);
  }

  /**
   * Attaches {@code message} to {@code spec}, encoded for the mode: the binary wire form, or
   * canonical proto3 JSON.
   *
   * <p>The two branches call different RestAssured overloads on purpose. {@code body(Object)} runs
   * RestAssured's object mapping, which has no serialiser for {@code application/x-protobuf} and
   * fails with "cannot determine how to serialize content-type" — so the bytes must reach
   * {@code body(byte[])} with that static type rather than through an {@code Object} the helper
   * returned.
   *
   * @throws InvalidProtocolBufferException if the message cannot be rendered as proto3 JSON
   */
  public static RequestSpecification body(RequestSpecification spec, String mode, Message message)
      throws InvalidProtocolBufferException {
    if (PROTOBUF.equals(mode)) {
      byte[] binary = message.toByteArray();
      return spec.body(binary);
    }
    return spec.body(JsonFormat.printer().print(message));
  }

  /**
   * Decodes a response body in the given mode into {@code builder}, after asserting the response
   * came back in the mode it was asked for.
   *
   * <p><strong>The echo assertion is the point, not a formality.</strong> A server that quietly
   * answered every request in JSON regardless of the header would pass a test that only parsed the
   * body as JSON, and the Protobuf client would be the one to discover it.
   */
  public static <B extends Message.Builder> B decode(String mode, Response response, B builder)
      throws InvalidProtocolBufferException {
    assertEquals(mode, response.getHeader(TRANSPORT_HEADER), "the response must echo its transport mode");
    if (PROTOBUF.equals(mode)) {
      assertTrue(
          response.getContentType().startsWith(PROTOBUF_TYPE),
          "protobuf mode must answer with " + PROTOBUF_TYPE + ", got " + response.getContentType());
      builder.mergeFrom(response.getBody().asByteArray());
    } else {
      assertTrue(
          response.getContentType().startsWith("application/json"),
          "json mode must answer with application/json, got " + response.getContentType());
      JsonFormat.parser().merge(response.getBody().asString(), builder);
    }
    return builder;
  }
}
