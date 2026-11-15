-- Statement import sessions (M6, jlogicsoftware/prudent#72, ADR-089).
--
-- TWO NEW TABLES, for the reason prudent_plan and prudent_goal give: an import session is a staging
-- area for statement rows the user has not yet confirmed, so it must not be able to reach a balance
-- or an analytics total. Nothing that sums prudent_record reads these tables.
--
-- THE UPLOADED STATEMENT IS NOT HERE AND HAS NOWHERE TO BE: there is no bytea or oversized text
-- column, only the normalised rows the importer produced. A row carries personal data (a description
-- and a counterparty), so the application deletes a session's rows when the session ends -- committed,
-- discarded or expired -- and keeps only the session row and its counts. The retention cascade for an
-- anonymised user (PrudentDataEraser) removes whatever is left.
--
-- NO FOREIGN KEY TO prudent_account. A session may name its destination account before any commit, and
-- an account delete (ADR-081) must not be blocked or cascaded by a staging row; the commit phase
-- re-checks that the account exists, is the caller's, is active and holds the session's currency.
-- Like every Prudent table, there is no ON DELETE CASCADE (ADR-010): the application deletes rows
-- before their session.
--
-- THIS FILE IS IMMUTABLE ONCE APPLIED, INCLUDING ITS COMMENTS (see V20260817090000__prudent_init).

CREATE TABLE prudent_import_session (
    id                UUID         PRIMARY KEY,
    user_id           UUID         NOT NULL,
    -- Names the importer (prudent.imports.StatementImporter#formatId), e.g. 'erste-pl-csv'. Not a
    -- CHECK list: the set of formats is code, and a new bank must not need a migration.
    format_id         TEXT         NOT NULL,
    -- Persisted by NAME (see prudent.imports.ImportState), so the CHECK below is the list of states
    -- the application may write.
    state             TEXT         NOT NULL DEFAULT 'PARSED',
    -- The destination account, once chosen. Deliberately no FOREIGN KEY; see the header.
    account_id        UUID,
    -- A SHA-256 digest (64 lower-case hex) of the statement's own account number, produced by the
    -- importer, or NULL for a format that carries no account identity. Kept so that the destination
    -- account can be re-checked every time it is set or replaced, which the statement itself cannot
    -- do once it has been dropped. It is personal data (an unsalted digest of a short number can be
    -- guessed): the application clears it when the session ends and never sends it over the wire.
    statement_identity CHAR(64),
    -- One currency per session; a statement mixing currencies is rejected before a session exists.
    currency          CHAR(3)      NOT NULL,
    created_at        TIMESTAMPTZ  NOT NULL,
    state_changed_at  TIMESTAMPTZ  NOT NULL,
    -- After this instant the session may not be previewed or committed and its rows are deleted.
    expires_at        TIMESTAMPTZ  NOT NULL,
    -- Counts as last classified; they outlive the rows, which are deleted when the session ends.
    accepted_rows     INTEGER      NOT NULL DEFAULT 0,
    duplicate_rows    INTEGER      NOT NULL DEFAULT 0,
    rejected_rows     INTEGER      NOT NULL DEFAULT 0,

    CONSTRAINT prudent_import_session_state_known
        CHECK (state IN ('PARSED', 'PREVIEWED', 'COMMITTED', 'DISCARDED', 'EXPIRED')),
    CONSTRAINT prudent_import_session_identity_is_digest
        CHECK (statement_identity IS NULL OR statement_identity ~ '^[0-9a-f]{64}$'),
    CONSTRAINT prudent_import_session_format_not_blank CHECK (length(btrim(format_id)) > 0),
    -- "pln" and "PLN" would otherwise be two currencies for one session.
    CONSTRAINT prudent_import_session_currency_upper CHECK (currency = upper(currency)),
    CONSTRAINT prudent_import_session_counts_not_negative
        CHECK (accepted_rows >= 0 AND duplicate_rows >= 0 AND rejected_rows >= 0),
    CONSTRAINT prudent_import_session_expiry_after_creation CHECK (expires_at > created_at)
);

-- The list is the caller's sessions, newest first; the expiry sweep reads by state and expiry.
CREATE INDEX prudent_import_session_user_idx ON prudent_import_session (user_id, created_at);
CREATE INDEX prudent_import_session_expiry_idx ON prudent_import_session (state, expires_at);

CREATE TABLE prudent_import_row (
    id                    UUID         PRIMARY KEY,
    -- No ON DELETE CASCADE (ADR-010); the application deletes rows before their session.
    session_id            UUID         NOT NULL REFERENCES prudent_import_session (id),
    user_id               UUID         NOT NULL,
    -- 1-based position among the statement's transaction rows, as the importer counted them.
    row_number            INTEGER      NOT NULL,
    -- ACCEPTED is written on commit; DUPLICATE is set only by a preview stage (#75); REJECTED rows are
    -- flagged, never dropped silently, and never written.
    status                TEXT         NOT NULL,
    -- A short stable rule code, never row content. Required exactly when the row is REJECTED.
    rejection_code        TEXT,
    transaction_date      DATE,
    booking_date          DATE,
    -- SIGNED minor units, like prudent_record.amount_minor: negative is money out.
    amount_minor          BIGINT,
    description           TEXT,
    counterparty          TEXT,
    counterparty_account  TEXT,
    external_id           TEXT,

    CONSTRAINT prudent_import_row_unique_number UNIQUE (session_id, row_number),
    CONSTRAINT prudent_import_row_number_positive CHECK (row_number > 0),
    CONSTRAINT prudent_import_row_status_known
        CHECK (status IN ('ACCEPTED', 'DUPLICATE', 'REJECTED')),
    -- A row that may be written must say when and how much; a rejected row may be missing either,
    -- because that can be exactly why it was rejected.
    CONSTRAINT prudent_import_row_writable_is_complete
        CHECK (status = 'REJECTED' OR (transaction_date IS NOT NULL AND amount_minor IS NOT NULL)),
    CONSTRAINT prudent_import_row_rejection_code_iff_rejected
        CHECK ((status = 'REJECTED') = (rejection_code IS NOT NULL AND length(btrim(rejection_code)) > 0)),
    CONSTRAINT prudent_import_row_amount_not_zero CHECK (amount_minor IS NULL OR amount_minor <> 0)
);

CREATE INDEX prudent_import_row_session_idx ON prudent_import_row (session_id, row_number);
CREATE INDEX prudent_import_row_user_idx ON prudent_import_row (user_id);

-- A table in public is exposed to the Supabase Data API until RLS says otherwise; see the init
-- migration. The zen_runtime policies are in R__prudent_row_level_security.sql, which lists both
-- tables in the same change.
ALTER TABLE prudent_import_session ENABLE ROW LEVEL SECURITY;
ALTER TABLE prudent_import_row ENABLE ROW LEVEL SECURITY;
