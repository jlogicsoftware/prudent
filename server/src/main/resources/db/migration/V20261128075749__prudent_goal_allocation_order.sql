-- The envelope history is read in the order it was recorded (jlogicsoftware/prudent#284, ADR-139).
--
-- It used to be ordered by created_at, then id. created_at is read from the application's clock, so
-- two entries can carry the same instant, and the id that then decided between them is random: the
-- order of two entries recorded one after the other could come out either way. A clock that stepped
-- back, or two instances whose clocks differ, reordered them as well.
--
-- recorded_seq is assigned by the database when the row is inserted, and the history is ordered by it
-- alone, newest first. It is unique, so the order is total, and no clock takes part in it.
--
-- WHAT THE NUMBER MEANS FOR CONCURRENT WRITES. It is the order of the inserts, not of the commits.
-- An entry is inserted while its transaction holds row locks it keeps until it commits: those of
-- every goal it names and, for an ALLOCATE, of every goal in the currency. So two entries whose
-- locked goals overlap are numbered in the order they commit. Two entries whose locked goals do not
-- overlap may commit in the other order: a read in between sees the higher number alone, and the
-- lower one appears below it afterwards. Numbers once visible never change places. A rolled-back
-- insert leaves a gap; nothing reads the numbers as a count.
--
-- CACHE 1 (the default) IS LOAD-BEARING. A cached sequence hands each database session a block of
-- numbers, and entries written through different pooled connections would then be numbered out of
-- order. Do not raise it.
--
-- GENERATED ALWAYS: a writer that names a value is refused, so the database stays the only source.
-- An identity column needs no grant on its sequence: INSERT on the table is enough.
--
-- THIS FILE IS IMMUTABLE ONCE APPLIED, INCLUDING ITS COMMENTS (see V20260817090000__prudent_init).

ALTER TABLE prudent_goal_allocation ADD COLUMN recorded_seq BIGINT;

-- THE BACKFILL. Rows that already exist were never numbered, and the order they were recorded in is
-- known only as far as created_at says. They are numbered oldest first, and within one instant by id
-- descending, so that "newest number first" shows exactly the order the history showed before
-- (created_at descending, then id ascending).
--
-- The append-only trigger refuses every UPDATE, this one included, so it is switched off around the
-- single statement that fills the new column. Flyway runs this file in one transaction, and the
-- ALTER above already holds the table exclusively until it ends: no other writer can reach the table
-- while the trigger is off, and a failure rolls the trigger's state back with everything else.
ALTER TABLE prudent_goal_allocation DISABLE TRIGGER prudent_goal_allocation_immutable;

UPDATE prudent_goal_allocation entry
   SET recorded_seq = numbered.seq
  FROM (SELECT id, row_number() OVER (ORDER BY created_at, id DESC) AS seq
          FROM prudent_goal_allocation) numbered
 WHERE entry.id = numbered.id;

ALTER TABLE prudent_goal_allocation ENABLE TRIGGER prudent_goal_allocation_immutable;

ALTER TABLE prudent_goal_allocation ALTER COLUMN recorded_seq SET NOT NULL;
ALTER TABLE prudent_goal_allocation ALTER COLUMN recorded_seq ADD GENERATED ALWAYS AS IDENTITY;

-- A new identity sequence starts at 1; continue after the backfilled rows. is_called = false makes
-- the value given the next one handed out, so an empty table starts at 1.
SELECT setval(
    pg_get_serial_sequence('prudent_goal_allocation', 'recorded_seq'),
    (SELECT COALESCE(max(recorded_seq), 0) + 1 FROM prudent_goal_allocation),
    false);

ALTER TABLE prudent_goal_allocation
    ADD CONSTRAINT prudent_goal_allocation_recorded_seq_unique UNIQUE (recorded_seq);

-- The history is the caller's entries by recorded_seq now; the (user_id, created_at) index served
-- only the old order.
DROP INDEX prudent_goal_allocation_user_idx;
CREATE INDEX prudent_goal_allocation_user_seq_idx
    ON prudent_goal_allocation (user_id, recorded_seq DESC);
