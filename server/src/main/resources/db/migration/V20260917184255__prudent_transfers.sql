-- Same-currency transfers (jlogicsoftware/prudent#32). A transfer is two linked records: the
-- source leg (negative amount_minor) and the destination leg (positive amount_minor), tied by
-- transfer_id. No new table -- the two rows ARE the transfer, and balance is derived (ADR-014),
-- so persisting both rows in one transaction is the entire "atomic balance update."

-- A transfer leg carries no category: it is neither income nor expense, so it has no spend
-- category to assign. Ordinary records still always have one -- RecordResource still requires it
-- on create/replace; only the column itself becomes nullable.
ALTER TABLE prudent_record ALTER COLUMN category_id DROP NOT NULL;

ALTER TABLE prudent_record ADD COLUMN transfer_id UUID;

-- Partial: transfer_id is null for the overwhelming majority of rows (every ordinary record), and
-- the only lookup pattern is "both legs by transfer_id" (TransferResource's delete).
CREATE INDEX prudent_record_transfer_idx ON prudent_record (transfer_id) WHERE transfer_id IS NOT NULL;
