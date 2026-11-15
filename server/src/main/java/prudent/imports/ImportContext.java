package prudent.imports;

import java.util.UUID;

/**
 * What an importer is told about the request besides the bytes: who is importing and, if they have
 * already chosen one, into which account. <strong>Do not check the statement's account identity
 * here:</strong> the destination can still be set or replaced after the parse, so the check lives
 * in {@link StatementImporter#checkDestination}, which the workflow runs on every assignment (the
 * Erste contract's account check, jlogicsoftware/prudent#73, is that method). The account is passed
 * only for a format that needs it to read the file.
 *
 * @param userId the caller; an importer must never read another user's data
 * @param accountId the destination account, already verified to be the caller's, or {@code null}
 */
public record ImportContext(UUID userId, UUID accountId) {}
