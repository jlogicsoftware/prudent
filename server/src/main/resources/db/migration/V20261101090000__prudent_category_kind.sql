-- Which side of the ledger a category files records on (jlogicsoftware/prudent#229).
--
-- 0 = unspecified (usable for both directions), 1 = expense, 2 = income, matching CategoryKind in
-- categories.proto. Every existing row gets 0, so no category a user already filed under changes
-- meaning; a new one is given a kind by the client.
--
-- THIS FILE IS IMMUTABLE ONCE APPLIED, INCLUDING ITS COMMENTS (see V20260817090000__prudent_init).

ALTER TABLE prudent_category
    ADD COLUMN kind SMALLINT NOT NULL DEFAULT 0 CHECK (kind IN (0, 1, 2));
