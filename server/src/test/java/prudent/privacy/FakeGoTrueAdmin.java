package prudent.privacy;

import jakarta.annotation.security.PermitAll;
import jakarta.ws.rs.DELETE;
import jakarta.ws.rs.HeaderParam;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.core.Response;
import java.util.List;
import java.util.concurrent.CopyOnWriteArrayList;

/**
 * Test-only stand-in for GoTrue's admin route, served by the test instance itself — {@code %test}
 * points {@link SupabaseAdminClient} here. It records what it was sent and answers with whatever
 * status a test has set, so the suite can drive every answer {@link SignInRecordEraser} has to
 * handle without a Supabase. That the real GoTrue accepts the call is proven against the local stack
 * by {@code client/integration_test/e2e_test.dart}, not here. Not part of the shipped server.
 */
@Path("/test-support/gotrue/auth/v1/admin/users")
@PermitAll
public class FakeGoTrueAdmin {

  /** One DELETE as it arrived. */
  public record Call(String userId, String apiKey, String authorization) {}

  private static final List<Call> CALLS = new CopyOnWriteArrayList<>();
  private static volatile int answer = 200;

  /** Forgets every call and goes back to answering 200. */
  public static void reset() {
    CALLS.clear();
    answer = 200;
  }

  /** Answers every later DELETE with {@code status}. */
  public static void answer(int status) {
    answer = status;
  }

  public static List<Call> calls() {
    return List.copyOf(CALLS);
  }

  @DELETE
  @Path("/{id}")
  public Response delete(
      @PathParam("id") String id,
      @HeaderParam("apikey") String apiKey,
      @HeaderParam("Authorization") String authorization) {
    CALLS.add(new Call(id, apiKey, authorization));
    return Response.status(answer).build();
  }
}
