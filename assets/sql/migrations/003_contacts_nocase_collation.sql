-- Migration 003: case-insensitive storage of the contact keys (cygnet3/dana issue 480).
-- Bech32 encodings are case-insensitive by construction, yet migration 000 declared
-- paymentCode and bip353Address as plain BINARY UNIQUE columns, so the two spellings
-- of one and the same destination coexisted as two distinct contacts and the
-- duplicate check in the add-contact sheet gave the wrong verdict.
-- The population is every install up to and including v0.8.3: those builds carry
-- neither sanitizePaymentCode() nor checkUpperCases(), so addContact() stored the
-- scanned or pasted string verbatim and one and the same destination could be
-- registered twice, once as SP1... and once as sp1..., in an order nobody knows.
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

-- The merge of the twins happens here, in the rebuild, and not by an UPDATE against
-- the old table. An UPDATE cannot do it: 000 already declares bip353Address UNIQUE
-- under the BINARY collation, so copying the address of the twin that is about to be
-- deleted onto the survivor collides with the row still holding it and aborts the
-- whole migration on the very first contact pair.
--   The survivor is the oldest row of the group, MIN(id), exactly as the re-attach
-- above keys the custom fields off it. Everything the doomed twins held and the
-- survivor lacks is taken over from the most recently created twin that has it,
-- since that is the save the user made last. A value the survivor already carries is
-- never replaced, so the tie-break stays what it is everywhere in this file: oldest
-- wins, holes are filled.
--   paymentCode is folded by lower(), which is what sanitizePaymentCode() produces at
-- runtime and what migration 002 wrote for tx_recipients, so the stored key agrees
-- with every key the current code writes. The fold is safe against the BINARY UNIQUE
-- of the old table because it runs on the way out, one row per NOCASE group, and no
-- two rows of one group can land on the same spelling twice. It is not cosmetic:
-- every contact lookup is case sensitive (ContactsRepository.getContactByPaymentCode
-- queries paymentCode = ? and the wallet joins its transaction history onto a contact
-- through that very query), so a survivor left as SP1... renders anonymous next to
-- its own transactions.
--   An address can still be worn by two contacts that never shared a payment code,
-- and the UNIQUE NOCASE key of the rebuilt table would refuse them and take the
-- migration down with them. That pair is not a duplicate of this deduplication,
-- which groups on paymentCode alone, so it is resolved here as well: the oldest of
-- those carriers keeps the address and the others give it up. Losing a label is
-- cheaper than a migration that aborts and leaves the database on the old BINARY
-- schema with every contact unfindable.
INSERT INTO contacts_new (id, name, bip353Address, paymentCode)
WITH merged AS (
  SELECT
    s.id AS id,
    COALESCE(
      s.name,
      (SELECT t.name FROM contacts AS t
        WHERE t.paymentCode = s.paymentCode COLLATE NOCASE
          AND t.name IS NOT NULL
        ORDER BY t.id DESC
        LIMIT 1)
    ) AS name,
    COALESCE(
      s.bip353Address,
      (SELECT t.bip353Address FROM contacts AS t
        WHERE t.paymentCode = s.paymentCode COLLATE NOCASE
          AND t.bip353Address IS NOT NULL
        ORDER BY t.id DESC
        LIMIT 1)
    ) AS bip353Address,
    lower(s.paymentCode) AS paymentCode
  FROM contacts AS s
  WHERE s.id IN (SELECT MIN(id) FROM contacts GROUP BY paymentCode COLLATE NOCASE)
)
SELECT
  merged.id,
  merged.name,
  CASE WHEN merged.bip353Address IS NOT NULL
        AND NOT EXISTS (
          SELECT 1 FROM merged AS other
           WHERE other.bip353Address IS NOT NULL
             AND other.bip353Address = merged.bip353Address COLLATE NOCASE
             AND other.id < merged.id
        )
       THEN merged.bip353Address
  END,
  merged.paymentCode
FROM merged;

INSERT INTO contact_fields_new (id, contact_id, field_type, field_value)
SELECT id, contact_id, field_type, field_value FROM contact_fields;

DROP TABLE contact_fields;

DROP TABLE contacts;

ALTER TABLE contacts_new RENAME TO contacts;

ALTER TABLE contact_fields_new RENAME TO contact_fields;

CREATE INDEX idx_contacts_bip353_address ON contacts(bip353Address);

CREATE INDEX idx_contacts_payment_code ON contacts(paymentCode);

CREATE INDEX idx_contact_fields_contact_id ON contact_fields(contact_id);
