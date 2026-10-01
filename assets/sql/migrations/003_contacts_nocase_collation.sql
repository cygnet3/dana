-- Migration 003: case-insensitive storage of the contact keys (cygnet3/dana issue 480).
-- Bech32 encodings are case-insensitive by construction, yet migration 000 declared
-- paymentCode and bip353Address as plain BINARY UNIQUE columns, so the two spellings
-- of one and the same destination coexisted as two distinct contacts and the
-- duplicate check in the add-contact sheet gave the wrong verdict.
-- SQLite has no ALTER COLUMN for a collation, so the parent must be rebuilt.
-- The child is rebuilt as well: with foreign_keys ON (see DatabaseHelper._onConfigure)
-- a DROP of the parent fires ON DELETE CASCADE into the untouched child and would wipe
-- every custom field. The rows of every merged pair are re-attached to the surviving
-- contact (oldest id wins) before the swap, so no field is ever cascade-deleted.
-- DatabaseHelper._performMigrations splits each file on the semicolon blindly,
-- therefore that character appears here only as a statement terminator and never
-- inside this comment block.

CREATE TABLE contacts_new (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT,
  bip353Address TEXT UNIQUE COLLATE NOCASE,
  paymentCode TEXT NOT NULL UNIQUE COLLATE NOCASE
);

CREATE TABLE contact_fields_new (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  contact_id INTEGER NOT NULL,
  field_type TEXT NOT NULL,
  field_value TEXT NOT NULL,
  FOREIGN KEY (contact_id) REFERENCES contacts_new (id) ON DELETE CASCADE
);

UPDATE contact_fields
SET contact_id = (
  SELECT MIN(winner.id)
  FROM contacts AS winner
  WHERE winner.paymentCode = (
    SELECT loser.paymentCode
    FROM contacts AS loser
    WHERE loser.id = contact_fields.contact_id
  ) COLLATE NOCASE
)
WHERE contact_id IN (
  SELECT id FROM contacts
  WHERE id NOT IN (
    SELECT MIN(id) FROM contacts GROUP BY paymentCode COLLATE NOCASE
  )
);

DELETE FROM contacts
WHERE id NOT IN (
  SELECT MIN(id) FROM contacts GROUP BY paymentCode COLLATE NOCASE
);

INSERT INTO contacts_new (id, name, bip353Address, paymentCode)
SELECT id, name, bip353Address, paymentCode FROM contacts;

INSERT INTO contact_fields_new (id, contact_id, field_type, field_value)
SELECT id, contact_id, field_type, field_value FROM contact_fields;

DROP TABLE contact_fields;

DROP TABLE contacts;

ALTER TABLE contacts_new RENAME TO contacts;

ALTER TABLE contact_fields_new RENAME TO contact_fields;

CREATE INDEX idx_contacts_bip353_address ON contacts(bip353Address);

CREATE INDEX idx_contacts_payment_code ON contacts(paymentCode);

CREATE INDEX idx_contact_fields_contact_id ON contact_fields(contact_id);