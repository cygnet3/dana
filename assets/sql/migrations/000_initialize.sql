CREATE TABLE contacts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT,
  bip353Address TEXT UNIQUE,
  paymentCode TEXT NOT NULL UNIQUE
);
CREATE INDEX idx_contacts_bip353_address ON contacts(bip353Address);
CREATE INDEX idx_contacts_payment_code ON contacts(paymentCode);
CREATE TABLE contact_fields (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  contact_id INTEGER NOT NULL,
  field_type TEXT NOT NULL,
  field_value TEXT NOT NULL,
  FOREIGN KEY (contact_id) REFERENCES contacts(id) ON DELETE CASCADE
);
CREATE INDEX idx_contact_fields_contact_id ON contact_fields(contact_id);
