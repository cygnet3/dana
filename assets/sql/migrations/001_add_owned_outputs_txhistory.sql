CREATE TABLE transactions (
  -- note: this is the table id, not txid
  -- we need this variable because we may detect transactions that we don't know the txid for
  id INTEGER PRIMARY KEY AUTOINCREMENT,

  txid TEXT UNIQUE,
  
  confirmation_height INTEGER,
  confirmation_blockhash TEXT,
  confirmation_timestamp INTEGER,
  
  user_note TEXT,
  user_note_updated_at INTEGER,
  
  created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
  updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
);
CREATE INDEX idx_transactions_confirmation_height ON transactions(confirmation_height);
CREATE INDEX idx_transactions_unconfirmed ON transactions(confirmation_height)
  WHERE confirmation_height IS NULL;

CREATE TABLE owned_outputs (
  txid TEXT NOT NULL,
  vout INTEGER NOT NULL,
  tweak BLOB NOT NULL,
  amount_sat INTEGER NOT NULL,
  script BLOB NOT NULL,
  label BLOB,
  created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
  PRIMARY KEY (txid, vout),
  FOREIGN KEY (txid) REFERENCES transactions(txid) ON DELETE CASCADE
);
CREATE INDEX idx_outputs_txid ON owned_outputs(txid);

CREATE TABLE tx_spent_outpoints (
  transaction_id INTEGER NOT NULL,
  outpoint_txid TEXT NOT NULL,
  outpoint_vout INTEGER NOT NULL,
  PRIMARY KEY (transaction_id, outpoint_txid, outpoint_vout),
  FOREIGN KEY (transaction_id) REFERENCES transactions(id) ON DELETE CASCADE,
  FOREIGN KEY (outpoint_txid, outpoint_vout) REFERENCES owned_outputs(txid, vout)
);
CREATE INDEX idx_tx_spent_outpoints_transaction_id ON tx_spent_outpoints(transaction_id);
CREATE INDEX idx_tx_spent_outpoints_outpoint ON tx_spent_outpoints(outpoint_txid, outpoint_vout);
CREATE TABLE tx_recipients (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  transaction_id INTEGER NOT NULL,
  payment_code TEXT NOT NULL,
  amount_sat INTEGER NOT NULL,
  FOREIGN KEY (transaction_id) REFERENCES transactions(id) ON DELETE CASCADE
);
CREATE INDEX idx_recipients_transaction_id ON tx_recipients(transaction_id);
CREATE INDEX idx_recipients_payment_code ON tx_recipients(payment_code);
