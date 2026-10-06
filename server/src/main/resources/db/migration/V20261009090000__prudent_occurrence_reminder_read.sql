-- Whether the user has read an occurrence's reminder (M5, jlogicsoftware/prudent#68, ADR-055).
--
-- A reminder is not a row. Whether an occurrence is due, and whether it is overdue, is worked out on
-- every read from its date, its plan's lead time and its plan's own calendar day (ADR-054, ADR-045).
-- The one fact about a reminder that is NOT derivable is that the user has seen it, so that is the
-- only thing stored, and it is stored on the occurrence the reminder is about. A second table would
-- be a one-to-one join, and would have a row to delete whenever an occurrence is deleted -- a
-- plan's edit and a plan's delete both do that -- where a column goes with its row.
--
-- NULL IS UNREAD, and it is what every occurrence has, including every one generated before this
-- migration and every one the generator inserts: it names no value. The timestamp (not a boolean)
-- is what the user did and when, and is kept at the first reading, so reading twice changes nothing.
--
-- THIS FILE IS IMMUTABLE ONCE APPLIED, INCLUDING ITS COMMENTS (see V20260817090000__prudent_init).

ALTER TABLE prudent_plan_occurrence
    ADD COLUMN reminder_read_at TIMESTAMPTZ;
