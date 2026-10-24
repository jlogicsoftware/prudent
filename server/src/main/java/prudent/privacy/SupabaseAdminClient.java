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
 * client sends the publishable key on behalf of a person, and this one sends the secret key on
 * behalf of the server. Keeping them apart means no call made for a person ever carries the key
 * that administers everyone.
 *
 * <p><strong>The secret key travels in {@code apikey} and nowhere else.</strong> It is not a JWT,
 * so it does not belong in {@code Authorization}; Supabase's gateway reads {@code apikey} and
 * presents the call to GoTrue as the service role. Measured against the local stack: an
 * {@code sb_secret_} key in {@code apikey} alone deletes a user (200, then 404 on a repeat), and the
 * publishable key is refused (403 {@code not_admin}). The legacy service-role JWT is not used at all
 * (ADR-075). The key is a parameter rather than a {@code @ClientHeaderParam} so that it is read and
 * checked in one place, {@link SignInRecordEraser}.
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
  void deleteUser(@PathParam("id") UUID userId, @HeaderParam("apikey") String secretKey);
}
