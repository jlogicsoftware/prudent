-- Category lifecycle: an inactive ("archived") state (M3, jlogicsoftware/prudent#62, ADR-047).
--
-- A CATEGORY THAT HAS BEEN USED IS NEVER DELETED; IT IS RETIRED. Records, plans, budgets and carry-over
-- resets all point at prudent_category with no ON DELETE CASCADE, so the database already refuses to
-- delete a referenced category. This column is the other half of that: a way to take a category out
-- of use without losing the name every one of those rows is read through.
--
-- A TIMESTAMP, NOT A BOOLEAN, so the history can say when the category stopped being in use. NULL is
-- the active state, which is what every existing row and every plain INSERT gets: nothing that
-- predates this migration changes meaning.
--
-- No index. A user has dozens of categories, and no query filters on this column: the list returns
-- every category with its state, because a record's category must stay readable once archived.
--
-- THIS FILE IS IMMUTABLE ONCE APPLIED, INCLUDING ITS COMMENTS (see V20260817090000__prudent_init).

ALTER TABLE prudent_category ADD COLUMN archived_at TIMESTAMPTZ;
