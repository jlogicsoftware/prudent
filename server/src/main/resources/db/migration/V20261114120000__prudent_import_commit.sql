-- Committing a statement import (M6, jlogicsoftware/prudent#76, ADR-092).
--
-- THREE THINGS NEED A PLACE TO LIVE.
--
-- 1. What the user decided about a row before confirming: a category and note (a ledger record of
--    the ordinary kind always has a category, so an import cannot invent one), and whether a row
--    marked DUPLICATE is in fact a new operation (include_duplicate). They are held with the row
--    and deleted with it when the session ends; category_id is a plain column with no foreign key,
--    like the session's account_id, so deleting a category is never blocked by staging data and the
--    commit re-validates it.
-- 2. What a finished commit did, so a retry of the same commit (a lost response, a second click)
--    can be answered with the same result: how many records it wrote and how many rows it found
--    already imported. Counts only; the rows themselves are gone.
-- 3. A session-wide default category per direction, so a statement of hundreds of rows is not
--    categorised one row at a time, and a stable hint code the importer may put on a row (for
--    example that it is an incoming transfer from the user's own account) so a client can warn.
--    The defaults, like a row's category, are plain columns with no foreign key; they are cleared
--    when the session ends.
--
-- THIS FILE IS IMMUTABLE ONCE APPLIED, INCLUDING ITS COMMENTS (see V20260817090000__prudent_init).

ALTER TABLE prudent_import_row
    ADD COLUMN category_id        UUID    NULL,
    ADD COLUMN note               TEXT    NULL,
    -- A short stable code the importer set at parse (never content), e.g. 'transfer.own_account'.
    ADD COLUMN hint_code          TEXT    NULL,
    ADD COLUMN include_duplicate  BOOLEAN NOT NULL DEFAULT FALSE,
    -- Only a row marked as a duplicate has anything to include; an accepted row is written anyway
    -- and a rejected one never is.
    ADD CONSTRAINT prudent_import_row_include_only_duplicate
        CHECK (NOT include_duplicate OR status = 'DUPLICATE'),
    ADD CONSTRAINT prudent_import_row_rejected_has_no_decision
        CHECK (status <> 'REJECTED' OR (category_id IS NULL AND note IS NULL)),
    -- Like every other note in the schema (budget resets, goal allocations): at most 500 characters.
    ADD CONSTRAINT prudent_import_row_note_length
        CHECK (note IS NULL OR char_length(note) <= 500),
    ADD CONSTRAINT prudent_import_row_hint_is_rule_code
        CHECK (hint_code IS NULL OR hint_code ~ '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$'),
    ADD CONSTRAINT prudent_import_row_rejected_has_no_hint
        CHECK (status <> 'REJECTED' OR hint_code IS NULL);

ALTER TABLE prudent_import_session
    ADD COLUMN committed_written           INTEGER NULL,
    ADD COLUMN committed_already_imported  INTEGER NULL,
    -- The category a row with no category of its own gets, by the sign of its amount. No foreign key.
    ADD COLUMN default_expense_category_id UUID    NULL,
    ADD COLUMN default_income_category_id  UUID    NULL,
    ADD CONSTRAINT prudent_import_session_commit_counts_paired
        CHECK ((committed_written IS NULL) = (committed_already_imported IS NULL)),
    ADD CONSTRAINT prudent_import_session_commit_counts_not_negative
        CHECK (committed_written IS NULL
               OR (committed_written >= 0 AND committed_already_imported >= 0)),
    -- Set exactly when the session is COMMITTED.
    ADD CONSTRAINT prudent_import_session_commit_counts_iff_committed
        CHECK ((state = 'COMMITTED') = (committed_written IS NOT NULL)),
    -- The defaults exist only while the session still holds rows.
    ADD CONSTRAINT prudent_import_session_defaults_only_while_open
        CHECK (state IN ('PARSED', 'PREVIEWED')
               OR (default_expense_category_id IS NULL AND default_income_category_id IS NULL));
