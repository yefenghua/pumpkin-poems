-- Parent accounts move from Sign in with Apple / dev subjects to an account ID
-- plus password. Existing rows belonged to the (never shipped) Apple flow and
-- cannot log in any more, so they are removed; the cascade clears their
-- sessions, profiles and synced data.
DELETE FROM parents;

ALTER TABLE parents
    DROP COLUMN subject,
    ADD COLUMN account_id    text NOT NULL,  -- lower case, see auth.NormalizeAccountID
    ADD COLUMN password_hash text NOT NULL;  -- PHC string, see auth.HashPassword
CREATE UNIQUE INDEX parents_account_id_idx ON parents (account_id);
