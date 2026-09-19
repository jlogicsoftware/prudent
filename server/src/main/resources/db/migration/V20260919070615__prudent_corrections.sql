-- Explicit balance corrections (M1, jlogicsoftware/prudent#53). A correction is an ordinary
-- prudent_record row, like a transfer leg -- no new table, because balance is derived (ADR-014)
-- and persisting the delta row IS the correction; there is no separate account state to update.
-- is_correction distinguishes it from an ordinary income/expense row so RecordResource can refuse
-- to edit/delete it directly and analytics can exclude it, the same way transfer_id already
-- distinguishes a transfer leg.

ALTER TABLE prudent_record ADD COLUMN is_correction BOOLEAN NOT NULL DEFAULT false;
