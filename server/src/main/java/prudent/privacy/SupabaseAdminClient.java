package prudent.privacy;

import jakarta.ws.rs.DELETE;
import jakarta.ws.rs.HeaderParam;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import java.util.UUID;
import org.eclipse.microprofile.rest.client.inject.RegisterRestClient;

/**
 * The one Supabase Auth (GoTrue) admin call Prudent makes: deleting a person's sign-in record.
 *
 * <p>The base URL ends in {@code /auth/v1} ({@code quarkus.rest-client.supabase-admin.url}), as for
 * the framework's own {@code SupabaseAuthClient}, so the path here is relative. It is a separate
 * client, under its own config key, because it carries a different credential: the framework's
 * client sends the anon key on behalf of a person, and this one sends the service-role key on
 * behalf of the server. Keeping them apart means no call made for a person ever carries the key
 * that administers everyone.
 *
 * <p>The key travels in both headers, as Supabase's own client libraries send it: GoTrue's admin
 * routes read the bearer token, and Supabase's gateway reads {@code apikey}. Measured against the
 * local stack, a legacy service-role JWT is refused (401) without the bearer, and both the legacy
 * key and an {@code sb_secret_} key are accepted with both headers. The key is a parameter rather
 * than a {@code @ClientHeaderParam} so that it is read in one place, {@link SignInRecordEraser},
 * which also refuses to send a blank one.
 *
 * <p>No body is sent, which GoTrue reads as a hard delete ({@code should_soft_delete} defaults to
 * false). Nothing is read from the answer either, so no JSON provider is involved — the server has
 * no Jackson, by rule.
 */
@RegisterRestClient(configKey = "supabase-admin")
public interface SupabaseAdminClient {

  /**
   * Deletes the sign-in record of {@code userId}. 200 when it existed, 404 ({@code user_not_found})
   * when it did not; the REST client throws for the second, which {@link SignInRecordEraser}
   * treats as already done.
   */
  @DELETE
  @Path("/admin/users/{id}")
  void deleteUser(
      @PathParam("id") UUID userId,
      @HeaderParam("apikey") String apiKey,
      @HeaderParam("Authorization") String bearer);
}
