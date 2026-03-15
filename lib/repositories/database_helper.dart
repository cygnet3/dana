import 'package:logger/logger.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('dana.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await _createDB(db, version);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        await _upgradeDB(db, oldVersion, newVersion);
      },
    );
  }

  Future _createDB(Database db, int version) async {
    Logger().i("Creating Database v$version");

    // Create all tables for fresh install
    await _createContactsTables(db);
    await _createWalletDataTables(db);
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    Logger().i("Upgrading Database from v$oldVersion to v$newVersion");

    if (oldVersion < 2) {
      // Add wallet data tables
      await _createWalletDataTables(db);
    }
  }

  Future _createContactsTables(Database db) async {
    const idType = 'INTEGER PRIMARY KEY AUTOINCREMENT';
    const textType = 'TEXT NOT NULL';
    const textTypeNullable = 'TEXT';
    const intType = 'INTEGER NOT NULL';

    await db.execute('''
    CREATE TABLE contacts (
      id $idType,
      name $textTypeNullable,
      bip353Address $textTypeNullable UNIQUE,
      paymentCode $textType UNIQUE
    )
    ''');

    await db.execute('''
    CREATE INDEX idx_contacts_bip353_address ON contacts(bip353Address)
    ''');

    await db.execute('''
    CREATE INDEX idx_contacts_payment_code ON contacts(paymentCode)
    ''');

    await db.execute('''
    CREATE TABLE contact_fields (
      id $idType,
      contact_id $intType,
      field_type $textType,
      field_value $textType,
      FOREIGN KEY (contact_id) REFERENCES contacts(id) ON DELETE CASCADE
    )
    ''');

    await db.execute('''
    CREATE INDEX idx_contact_fields_contact_id ON contact_fields(contact_id)
    ''');
  }

  Future _createWalletDataTables(Database db) async {
    Logger().i("Creating wallet data tables");

    // ============================================
    // OWNED OUTPUTS
    // ============================================
    await db.execute('''
    CREATE TABLE owned_outputs (
      txid TEXT NOT NULL,
      vout INTEGER NOT NULL,
      blockheight INTEGER NOT NULL,
      tweak BLOB NOT NULL,
      amount_sat INTEGER NOT NULL,
      script TEXT NOT NULL,
      label TEXT,
      spending_txid TEXT,
      mined_in_block TEXT,
      created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
      PRIMARY KEY (txid, vout)
    )
    ''');

    // Unspent outputs (for balance, spending)
    await db.execute('''
    CREATE INDEX idx_outputs_unspent ON owned_outputs(spending_txid, mined_in_block)
    WHERE spending_txid IS NULL AND mined_in_block IS NULL
    ''');

    // Spent but not yet mined (mempool)
    await db.execute('''
    CREATE INDEX idx_outputs_spent_unmined ON owned_outputs(spending_txid, mined_in_block)
    WHERE spending_txid IS NOT NULL AND mined_in_block IS NULL
    ''');

    // Spent or not, not yet mined (scanning)
    await db.execute('''
    CREATE INDEX idx_outputs_to_scan ON owned_outputs(mined_in_block)
    WHERE mined_in_block IS NULL
    ''');

    // For resetToHeight
    await db.execute('''
    CREATE INDEX idx_outputs_blockheight ON owned_outputs(blockheight)
    ''');

    // For querying outputs by txid
    await db.execute('''
    CREATE INDEX idx_outputs_txid ON owned_outputs(txid)
    ''');

    // ============================================
    // INCOMING TRANSACTIONS
    // Transactions where we received funds
    // ============================================
    await db.execute('''
    CREATE TABLE tx_incoming (
      txid TEXT PRIMARY KEY,
      
      amount_received_sat INTEGER NOT NULL,
      
      confirmation_height INTEGER,
      confirmation_blockhash TEXT,
      
      user_note TEXT,
      user_note_updated_at INTEGER,
      
      created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
      updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
    )
    ''');

    // For transaction list (ordered by confirmation)
    await db.execute('''
    CREATE INDEX idx_incoming_confirmation_height ON tx_incoming(confirmation_height)
    ''');

    // For unconfirmed incoming transactions
    await db.execute('''
    CREATE INDEX idx_incoming_unconfirmed ON tx_incoming(confirmation_height)
    WHERE confirmation_height IS NULL
    ''');

    // ============================================
    // OUTGOING TRANSACTIONS
    // Transactions where we spent funds
    // ============================================
    await db.execute('''
    CREATE TABLE tx_outgoing (
      txid TEXT PRIMARY KEY,
      
      amount_spent_sat INTEGER NOT NULL,
      change_sat INTEGER NOT NULL DEFAULT 0,
      fee_sat INTEGER NOT NULL DEFAULT 0,
      
      confirmation_height INTEGER,
      confirmation_blockhash TEXT,
      
      user_note TEXT,
      user_note_updated_at INTEGER,
      
      created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
      updated_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
    )
    ''');

    // For transaction list (ordered by confirmation)
    await db.execute('''
    CREATE INDEX idx_outgoing_confirmation_height ON tx_outgoing(confirmation_height)
    ''');

    // For unconfirmed outgoing transactions
    await db.execute('''
    CREATE INDEX idx_outgoing_unconfirmed ON tx_outgoing(confirmation_height)
    WHERE confirmation_height IS NULL
    ''');

    // For unconfirmed change calculation
    await db.execute('''
    CREATE INDEX idx_outgoing_unconfirmed_change ON tx_outgoing(confirmation_height, change_sat)
    WHERE confirmation_height IS NULL
    ''');

    // For self-send detection during scan
    await db.execute('''
    CREATE INDEX idx_outgoing_txid ON tx_outgoing(txid)
    ''');

    // ============================================
    // SPENT OUTPOINTS (for outgoing transactions)
    // Links tx_outgoing to the outputs we spent
    // ============================================
    await db.execute('''
    CREATE TABLE tx_spent_outpoints (
      txid TEXT NOT NULL,
      outpoint_txid TEXT NOT NULL,
      outpoint_vout INTEGER NOT NULL,
      PRIMARY KEY (txid, outpoint_txid, outpoint_vout),
      FOREIGN KEY (txid) REFERENCES tx_outgoing(txid) ON DELETE CASCADE,
      FOREIGN KEY (outpoint_txid, outpoint_vout) REFERENCES owned_outputs(txid, vout)
    )
    ''');

    await db.execute('''
    CREATE INDEX idx_spent_outpoints_txid ON tx_spent_outpoints(txid)
    ''');

    await db.execute('''
    CREATE INDEX idx_spent_outpoints_outpoint ON tx_spent_outpoints(outpoint_txid, outpoint_vout)
    ''');

    // ============================================
    // RECIPIENTS (for outgoing transactions)
    // Where we sent the money
    // ============================================
    await db.execute('''
    CREATE TABLE tx_recipients (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      txid TEXT NOT NULL,
      address TEXT NOT NULL,
      amount_sat INTEGER NOT NULL,
      FOREIGN KEY (txid) REFERENCES tx_outgoing(txid) ON DELETE CASCADE
    )
    ''');

    await db.execute('''
    CREATE INDEX idx_recipients_txid ON tx_recipients(txid)
    ''');

    await db.execute('''
    CREATE INDEX idx_recipients_address ON tx_recipients(address)
    ''');
  }

  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}
