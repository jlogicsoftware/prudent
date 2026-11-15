-- Duplicate detection for statement imports (M6, jlogicsoftware/prudent#75, ADR-091).
--
-- A statement row has no identifier that is known to survive a second, overlapping export (the
-- bank's sequence number looks like a rank from the newest row of THAT export, ADR-088), so a row
-- is recognised by a fingerprint: a one-way digest of what the row says, scoped to the destination
-- account, plus an OCCURRENCE number that tells apart rows with identical fingerprints inside one
-- statement (two genuine ticket purchases on one day are two rows, not one). The pair is a
-- row's key. It is computed at preview, held on the import row, and copied by the commit (#76) onto
-- the ledger record it creates, which is what a later preview compares against.
--
-- THE DIGEST IS NOT SECRET. The input is short and low-entropy (a date, an amount, a merchant), so
-- anyone holding the database can test guesses against it: it is personal data, kept with the row
-- that already carries user_id (RLS, the eraser and the account delete cover it), and it is never
-- sent over the wire. It exists so that no statement text has to sit in a column nothing reads.
--
-- THE KEY IS "v1:" (the fingerprint scheme) OR "e1:" (a format whose bank identifier is proven
-- stable) FOLLOWED BY 64 lower-case hex. The prefix is what lets a later scheme coexist with this
-- one: records keep the key they were imported with, and a record imported under another scheme
-- is simply not matched by this one.
--
-- THIS FILE IS IMMUTABLE ONCE APPLIED, INCLUDING ITS COMMENTS (see V20260817090000__prudent_init).

ALTER TABLE prudent_import_row
    ADD COLUMN fingerprint     TEXT    NULL,
    ADD COLUMN occurrence      INTEGER NULL,
    -- A short stable code (duplicate.already_imported), never row content. Only on a DUPLICATE row.
    ADD COLUMN duplicate_code  TEXT    NULL,
    ADD CONSTRAINT prudent_import_row_fingerprint_shape
        CHECK (fingerprint IS NULL OR fingerprint ~ '^[a-z][0-9]+:[0-9a-f]{64}$'),
    ADD CONSTRAINT prudent_import_row_key_paired
        CHECK ((fingerprint IS NULL) = (occurrence IS NULL)),
    ADD CONSTRAINT prudent_import_row_occurrence_positive
        CHECK (occurrence IS NULL OR occurrence > 0),
    -- A rejected row has nothing to fingerprint and nothing to be a duplicate of.
    ADD CONSTRAINT prudent_import_row_key_not_rejected
        CHECK (status <> 'REJECTED' OR fingerprint IS NULL),
    ADD CONSTRAINT prudent_import_row_duplicate_code_only_on_duplicate
        CHECK (duplicate_code IS NULL OR (status = 'DUPLICATE' AND length(btrim(duplicate_code)) > 0));

ALTER TABLE prudent_record
    ADD COLUMN import_fingerprint TEXT    NULL,
    ADD COLUMN import_occurrence  INTEGER NULL,
    ADD CONSTRAINT prudent_record_import_fingerprint_shape
        CHECK (import_fingerprint IS NULL OR import_fingerprint ~ '^[a-z][0-9]+:[0-9a-f]{64}$'),
    -- The two travel together, like plan_id and plan_occurrence_id.
    ADD CONSTRAINT prudent_record_import_key_paired
        CHECK ((import_fingerprint IS NULL) = (import_occurrence IS NULL)),
    ADD CONSTRAINT prudent_record_import_occurrence_positive
        CHECK (import_occurrence IS NULL OR import_occurrence > 0);

-- UNIQUE, NOT A PLAIN INDEX. A statement row may be written into an account once. Two commits of
-- overlapping sessions racing each other (two tabs, a retry after a timeout, two devices) can
-- both pass the preview's "not yet imported" check; the preview is advice, and this index is what
-- makes the second writer fail instead of doubling the ledger. #76 turns that failure into an
-- idempotent answer. Scoped to the account because the fingerprint already carries the account
-- and an account belongs to one user. Partial, because most records are not imported and NULLs
-- must not collide. A record the user deletes frees its key, so deleting an imported record and
-- importing the statement again brings that row back, which is what deleting it asked for.
CREATE UNIQUE INDEX prudent_record_import_key_unique
    ON prudent_record (account_id, import_fingerprint, import_occurrence)
    WHERE import_fingerprint IS NOT NULL;
