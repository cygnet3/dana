CREATE TABLE owned_outputs (
  txid TEXT NOT NULL,
  vout INTEGER NOT NULL,
  blockheight INTEGER NOT NULL,
  tweak BLOB NOT NULL,
  amount INTEGER NOT NULL,
  script TEXT NOT NULL,
  label TEXT,
  created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
  PRIMARY KEY (txid, vout)
);
CREATE INDEX idx_outputs_blockheight ON owned_outputs(blockheight);
CREATE INDEX idx_outputs_txid ON owned_outputs(txid);

-- INCOMING TRANSACTIONS
-- Transactions where we received funds
CREATE TABLE tx_incoming (
  txid TEXT PRIMARY KEY,
  
  amount_received_sat INTEGER NOT NULL,
  
  confirmation_height INTEGER,
  confirmation_blockhash TEXT,
  confirmation_timestamp INTEGER,
  
  user_note TEXT,
  user_note_updated_at INTEGER,
  
  created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
  updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
);
CREATE INDEX idx_incoming_confirmation_height ON tx_incoming(confirmation_height);
CREATE INDEX idx_incoming_unconfirmed ON tx_incoming(confirmation_height)
  WHERE confirmation_height IS NULL;
CREATE INDEX idx_incoming_missing_confirmation_timestamp ON tx_incoming(confirmation_height, confirmation_blockhash)
  WHERE confirmation_height IS NOT NULL AND confirmation_blockhash IS NOT NULL AND confirmation_timestamp IS NULL;

-- OUTGOING TRANSACTIONS
-- Transactions where we spent funds
CREATE TABLE tx_outgoing (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  txid TEXT UNIQUE,
  
  amount_spent_sat INTEGER NOT NULL,
  change_sat INTEGER,
  fee_sat INTEGER,
  
  confirmation_height INTEGER,
  confirmation_blockhash TEXT,
  confirmation_timestamp INTEGER,
  
  user_note TEXT,
  user_note_updated_at INTEGER,
  
  created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
  updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
);
CREATE INDEX idx_outgoing_confirmation_height ON tx_outgoing(confirmation_height);
CREATE INDEX idx_outgoing_unconfirmed ON tx_outgoing(confirmation_height)
  WHERE confirmation_height IS NULL;
CREATE INDEX idx_outgoing_unconfirmed_change ON tx_outgoing(confirmation_height, change_sat)
  WHERE confirmation_height IS NULL;
CREATE INDEX idx_outgoing_txid ON tx_outgoing(txid);
CREATE INDEX idx_outgoing_missing_confirmation_timestamp ON tx_outgoing(confirmation_height, confirmation_blockhash)
  WHERE confirmation_height IS NOT NULL AND confirmation_blockhash IS NOT NULL AND confirmation_timestamp IS NULL;

-- SPENT OUTPOINTS (for outgoing transactions)
-- Links tx_outgoing to the outputs we spent
CREATE TABLE tx_spent_outpoints (
  tx_outgoing_id INTEGER NOT NULL,
  outpoint_txid TEXT NOT NULL,
  outpoint_vout INTEGER NOT NULL,
  PRIMARY KEY (tx_outgoing_id, outpoint_txid, outpoint_vout),
  FOREIGN KEY (tx_outgoing_id) REFERENCES tx_outgoing(id) ON DELETE CASCADE,
  FOREIGN KEY (outpoint_txid, outpoint_vout) REFERENCES owned_outputs(txid, vout)
);
CREATE INDEX idx_spent_outpoints_tx_outgoing_id ON tx_spent_outpoints(tx_outgoing_id);
CREATE INDEX idx_spent_outpoints_outpoint ON tx_spent_outpoints(outpoint_txid, outpoint_vout);
CREATE TABLE tx_recipients (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  tx_outgoing_id INTEGER NOT NULL,
  payment_code TEXT NOT NULL,
  amount INTEGER NOT NULL,
  FOREIGN KEY (tx_outgoing_id) REFERENCES tx_outgoing(id) ON DELETE CASCADE
);
CREATE INDEX idx_recipients_tx_outgoing_id ON tx_recipients(tx_outgoing_id);
CREATE INDEX idx_recipients_payment_code ON tx_recipients(payment_code);
