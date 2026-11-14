-- The bank number of an account (M6, jlogicsoftware/prudent#73, ADR-090).
--
-- OPTIONAL, AND NORMALISED BY THE SERVER BEFORE IT IS STORED: whitespace removed, upper-cased, a
-- leading PL dropped from a 26-digit number. A statement importer compares the statement's own
-- account with this column before any row may be written into the account, and an own-account
-- transfer's other leg is recognised by it. NULL means "no number stored", and the importer then
-- refuses (fail closed) rather than guess. No backfill: an existing account has no number until its
-- owner supplies one.
--
-- THE CHECK IS A SHAPE, NOT A CHECKSUM. The synthetic fixtures use check digits 00, which no real
-- IBAN has, so a mod-97 test would refuse every test account; a mistyped number is caught by the
-- importer's mismatch instead.
--
-- AT MOST ONE ACCOUNT PER USER HOLDS A GIVEN NUMBER. Two would make "the account this statement is
-- for" and "the account the other leg of a transfer went to" ambiguous. The column is personal data
-- and carries the owner's user_id like the rest of the row, so the privacy export and eraser already
-- cover it.
--
-- THIS FILE IS IMMUTABLE ONCE APPLIED, INCLUDING ITS COMMENTS (see V20260817090000__prudent_init).

ALTER TABLE prudent_account
    ADD COLUMN account_number TEXT NULL;

ALTER TABLE prudent_account
    ADD CONSTRAINT prudent_account_number_shape CHECK (account_number ~ '^[A-Z0-9]{10,34}$');

CREATE UNIQUE INDEX prudent_account_number_unique
    ON prudent_account (user_id, account_number)
    WHERE account_number IS NOT NULL;
