-- Payee and note fields for records (jlogicsoftware/prudent#51). Both are optional metadata
-- alongside title: payee is who the money moved to or from, note is free-form detail. Additive
-- and nullable -- existing records are unaffected and read back with both columns absent.
ALTER TABLE prudent_record ADD COLUMN payee TEXT;
ALTER TABLE prudent_record ADD COLUMN note  TEXT;
