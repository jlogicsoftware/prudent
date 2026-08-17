package prudent.server;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.security.TestSecurity;
import io.restassured.response.Response;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import prudent.proto.v1.Category;
import prudent.proto.v1.CreateCategoryRequest;
import prudent.proto.v1.ListCategoriesResponse;
import prudent.proto.v1.UpdateCategoryRequest;
import zen.proto.v1.ZenError;

/**
 * The category surface: full CRUD in both transport modes, and the two refusals the resource owns.
 *
 * <p>Each CRUD test is parameterised over {@code json} and {@code protobuf} rather than written
 * twice, so the two modes cannot drift apart in coverage — a mode tested only for reads is a mode
 * whose writes nobody checked.
 */
@QuarkusTest
class CategoryResourceTest {

  @BeforeEach
  void reset() {
    PrudentTest.reset();
  }

  @ParameterizedTest
  @ValueSource(strings = {PrudentTest.JSON, PrudentTest.PROTOBUF})
  @TestSecurity(user = PrudentTest.ALICE)
  void crud_roundTrips(String mode) throws Exception {
    // CREATE
    CreateCategoryRequest create =
        CreateCategoryRequest.newBuilder()
            .setTitle("Groceries")
            .setIconKey("food")
            .setDescription("Weekly shop")
            .setColorArgb(0xFF4CAF50)
            .build();

    Response created =
        PrudentTest.body(PrudentTest.request(mode), mode, create)
            .when()
            .post("/api/v1/categories")
            .andReturn();

    assertEquals(201, created.statusCode());
    Category category =
        PrudentTest.decode(mode, created, Category.newBuilder()).build();

    // THE ID IS SERVER-MINTED. The request had no id field to carry one, and the response is where
    // the client first learns it.
    assertFalse(category.getId().isBlank(), "the create response must carry a server-minted id");
    assertEquals("Groceries", category.getTitle());
    assertEquals("food", category.getIconKey());
    assertEquals("Weekly shop", category.getDescription());
    assertEquals(0xFF4CAF50, category.getColorArgb());

    // READ
    Response read =
        PrudentTest.request(mode)
            .when()
            .get("/api/v1/categories/" + category.getId())
            .andReturn();
    assertEquals(200, read.statusCode());
    assertEquals(category, PrudentTest.decode(mode, read, Category.newBuilder()).build());

    // LIST
    Response listed = PrudentTest.request(mode).when().get("/api/v1/categories").andReturn();
    assertEquals(200, listed.statusCode());
    ListCategoriesResponse list =
        PrudentTest.decode(mode, listed, ListCategoriesResponse.newBuilder()).build();
    assertEquals(1, list.getCategoriesCount());
    assertEquals(category, list.getCategories(0));

    // UPDATE — a full replacement: the description is deliberately omitted from the request and
    // must come back empty, because that is what a full replacement means.
    UpdateCategoryRequest update =
        UpdateCategoryRequest.newBuilder()
            .setTitle("Food")
            .setIconKey("restaurant")
            .setColorArgb(0xFFFF9800)
            .build();
    Response updated =
        PrudentTest.body(PrudentTest.request(mode), mode, update)
            .when()
            .put("/api/v1/categories/" + category.getId())
            .andReturn();
    assertEquals(200, updated.statusCode());
    Category replaced = PrudentTest.decode(mode, updated, Category.newBuilder()).build();
    assertEquals(category.getId(), replaced.getId(), "an update must not re-mint the id");
    assertEquals("Food", replaced.getTitle());
    assertEquals("restaurant", replaced.getIconKey());
    assertEquals(0xFFFF9800, replaced.getColorArgb());
    assertEquals(
        "",
        replaced.getDescription(),
        "PUT is a full replacement: an omitted field is written as its proto3 default, not merged");

    // DELETE
    Response deleted =
        PrudentTest.request(mode)
            .when()
            .delete("/api/v1/categories/" + category.getId())
            .andReturn();
    assertEquals(204, deleted.statusCode());

    Response gone =
        PrudentTest.request(mode)
            .when()
            .get("/api/v1/categories/" + category.getId())
            .andReturn();
    assertEquals(404, gone.statusCode());
  }

  @ParameterizedTest
  @ValueSource(strings = {PrudentTest.JSON, PrudentTest.PROTOBUF})
  @TestSecurity(user = PrudentTest.ALICE)
  void unknownIconKey_isRejectedWithZenError(String mode) throws Exception {
    CreateCategoryRequest create =
        CreateCategoryRequest.newBuilder()
            .setTitle("Rocketry")
            .setIconKey("rocket")
            .setColorArgb(0xFF000000)
            .build();

    Response response =
        PrudentTest.body(PrudentTest.request(mode), mode, create)
            .when()
            .post("/api/v1/categories")
            .andReturn();

    assertEquals(400, response.statusCode());
    // THE SHAPE, not only the status. A client branches on `code`, so a refusal that arrived with
    // the right status and an empty body would still break it.
    ZenError error = PrudentTest.decode(mode, response, ZenError.newBuilder()).build();
    assertEquals("invalid", error.getCode());
    assertTrue(
        error.getMessage().contains("rocket"),
        "the message should name the offending key, was: " + error.getMessage());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void blankTitle_isRejected() throws Exception {
    CreateCategoryRequest create =
        CreateCategoryRequest.newBuilder().setTitle("   ").setIconKey("food").build();

    Response response =
        PrudentTest.body(PrudentTest.request(PrudentTest.JSON), PrudentTest.JSON, create)
            .when()
            .post("/api/v1/categories")
            .andReturn();

    assertEquals(400, response.statusCode());
    assertEquals(
        "invalid",
        PrudentTest.decode(PrudentTest.JSON, response, ZenError.newBuilder()).build().getCode());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void unknownId_returnsZenErrorNotFound() throws Exception {
    Response response =
        PrudentTest.request(PrudentTest.JSON)
            .when()
            .get("/api/v1/categories/" + java.util.UUID.randomUUID())
            .andReturn();

    assertEquals(404, response.statusCode());
    ZenError error =
        PrudentTest.decode(PrudentTest.JSON, response, ZenError.newBuilder()).build();
    assertEquals("not_found", error.getCode());
    assertNotNull(error.getMessage());
    assertFalse(error.getMessage().isBlank());
  }

  @Test
  @TestSecurity(user = PrudentTest.ALICE)
  void malformedId_isNotFoundRatherThanAServerError() throws Exception {
    // UUID.fromString throws IllegalArgumentException, which JAX-RS would render as a bare 500 with
    // no body — leaving a ZenClient that parses ZenError on any status >= 400 to report a decode
    // failure whose cause has nothing to do with the typo that produced it.
    Response response =
        PrudentTest.request(PrudentTest.JSON)
            .when()
            .get("/api/v1/categories/not-a-uuid")
            .andReturn();

    assertEquals(404, response.statusCode());
    assertEquals(
        "not_found",
        PrudentTest.decode(PrudentTest.JSON, response, ZenError.newBuilder()).build().getCode());
  }

  @Test
  void anonymous_isRefused() {
    // @Authenticated, not @RolesAllowed(USER): roles are single and have no hierarchy, so gating on
    // USER would 403 an admin. This asserts the gate exists at all.
    Response response =
        PrudentTest.request(PrudentTest.JSON).when().get("/api/v1/categories").andReturn();
    assertEquals(401, response.statusCode());
  }
}
