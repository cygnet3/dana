import 'dart:convert';
import 'dart:typed_data';

import 'package:danawallet/data/models/bip353_address.dart';
import 'package:danawallet/data/models/dana_backup.dart';
import 'package:danawallet/extensions/date_time.dart';
import 'package:danawallet/generated/rust/api/history.dart';
import 'package:danawallet/generated/rust/api/structs/amount.dart';
import 'package:danawallet/generated/rust/api/structs/discovered_output.dart';
import 'package:danawallet/generated/rust/api/structs/network.dart';
import 'package:danawallet/generated/rust/api/structs/recipient.dart';
import 'package:danawallet/generated/rust/api/structs/recorded_transaction.dart';
import 'package:danawallet/generated/rust/api/wallet.dart';
import 'package:danawallet/generated/rust/api/wallet/setup.dart';
import 'package:danawallet/generated/rust/lib.dart';
import 'package:danawallet/repositories/database_helper.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

// secure storage
const String _keyScanSk = "scansk";
const String _keySpendKey = "spendkey";
const String _keySeedPhrase = "seedphrase";

// non secure storage (SharedPreferences - will be migrated to SQLite)
const String _keyBirthday = "birthday";
const String _keyNetwork = "network";
const String _keyTxHistory = "txhistory";
const String _keyOwnedOutputs = "ownedoutputs"; // Legacy key, only used for cleanup
const String _keyLastScan = "lastscan";
const String _keyDanaAddress = "danaaddress";

class WalletRepository {
  final secureStorage = const FlutterSecureStorage();
  final nonSecureStorage = SharedPreferencesAsync();

  // private constructor
  WalletRepository._();

  // singleton class
  static final instance = WalletRepository._();

  Future<Database> get _db async => await DatabaseHelper.instance.database;

  // ============================================
  // MIGRATION
  // ============================================

  /// Check if migration from SharedPreferences is needed and perform it.
  /// Should be called on app startup before any wallet operations.
  ///
  /// LEGACY: This is the ONLY place where TxHistory should be used.
  /// TxHistory is kept in Rust only for migration from old app versions.
  Future<void> migrateToSqliteIfNeeded() async {
    final oldOutputs = await nonSecureStorage.getString(_keyOwnedOutputs);
    final oldHistory = await nonSecureStorage.getString(_keyTxHistory);

    if (oldOutputs == null && oldHistory == null) {
      return; // No migration needed
    }

    Logger().i("Migrating wallet data from SharedPreferences to SQLite");

    final db = await _db;

    await db.transaction((txn) async {
      // Migrate owned outputs (ad-hoc JSON decoding, no Rust dependency).
      // LEGACY: can be removed once no users remain on pre-SQLite versions.
      //
      // The old spend_status was a serde enum:
      //   "Unspent"              → spending_txid: null, mined_in_block: null
      //   {"Spent": "txid"}      → spending_txid: txid, mined_in_block: null
      //   {"Mined": "blockhash"} → spending_txid: null, mined_in_block: blockhash
      if (oldOutputs != null) {
        try {
          final Map<String, dynamic> decoded = jsonDecode(oldOutputs);
          int migrated = 0;

          for (final entry in decoded.entries) {
            final Map<String, dynamic> output = entry.value;
            final spendStatus = output['spend_status'];

            String? spendingTxid;
            String? minedInBlock;

            if (spendStatus is Map<String, dynamic>) {
              if (spendStatus.containsKey('Spent')) {
                spendingTxid = spendStatus['Spent'] as String?;
              } else if (spendStatus.containsKey('Mined')) {
                minedInBlock = spendStatus['Mined'] as String?;
              }
            }
            // else: "Unspent" string — both remain null

            final outpoint = _parseOutpoint(entry.key);
            final List<dynamic> tweakList = output['tweak'];

            await txn.insert('owned_outputs', {
              'txid': outpoint.$1,
              'vout': outpoint.$2,
              'blockheight': output['blockheight'] as int,
              'tweak': Uint8List.fromList(tweakList.cast<int>()),
              'amount_sat': output['amount'] as int,
              'script': output['script'] as String,
              'label': output['label'] as String?,
              'spending_txid': spendingTxid,
              'mined_in_block': minedInBlock,
            });
            migrated++;
          }

          Logger().i("Migrated $migrated outputs (of ${decoded.length} total)");
        } catch (e) {
          Logger().e("Failed to migrate owned outputs: $e");
          rethrow;
        }
      }

      // Migrate transaction history
      // LEGACY: TxHistory.decode() is only used here for migration
      if (oldHistory != null) {
        try {
          final history = TxHistory.decode(encodedHistory: oldHistory);
          final transactions = history.toApiTransactions();

          for (final tx in transactions) {
            await _insertTransactionInTxn(txn, tx);
          }

          Logger().i("Migrated ${transactions.length} transactions");
        } catch (e) {
          Logger().e("Failed to migrate transaction history: $e");
          rethrow;
        }
      }
    });

    // Remove old keys after successful migration
    await nonSecureStorage.remove(_keyOwnedOutputs);
    await nonSecureStorage.remove(_keyTxHistory);

    Logger().i("Migration complete");
  }

  // ============================================
  // WALLET SETUP & RESET
  // ============================================

  Future<void> reset() async {
    // delete secure storage
    await secureStorage.deleteAll();

    // delete non secure storage
    await nonSecureStorage.clear(allowList: {
      _keyNetwork,
      _keyTxHistory,
      _keyLastScan,
      _keyOwnedOutputs,
      _keyBirthday,
      _keyDanaAddress,
    });

    // clear SQLite wallet data
    final db = await _db;
    await db.delete('owned_outputs');
    await db.delete('tx_incoming');
    await db.delete('tx_outgoing');
  }

  Future<SpWallet> setupWallet(WalletSetupResult walletSetup,
      ApiNetwork network, DateTime? birthday, int? lastScan) async {
    if ((await secureStorage.readAll()).isNotEmpty) {
      throw Exception('Previous wallet not properly deleted');
    }

    // save variables in storage
    final scanKey = walletSetup.scanKey;
    final spendKey = walletSetup.spendKey;
    final seedPhrase = walletSetup.mnemonic;

    // insert new values
    await secureStorage.write(key: _keyScanSk, value: scanKey.encode());
    await secureStorage.write(key: _keySpendKey, value: spendKey.encode());
    await nonSecureStorage.setString(_keyNetwork, network.name);

    if (birthday != null) {
      await nonSecureStorage.setInt(_keyBirthday, birthday.toSeconds());
    }

    if (seedPhrase != null) {
      await secureStorage.write(key: _keySeedPhrase, value: seedPhrase);
    }

    // set default values for new wallet
    await saveLastScan(lastScan);

    // check if creation was successful by reading wallet
    final wallet = await readWallet();
    return wallet!;
  }

  Future<SpWallet?> readWallet() async {
    final scanKey = await readScanKey();
    final spendKey = await readSpendKey();

    if (scanKey != null && spendKey != null) {
      final network = await readNetwork();
      return SpWallet(scanKey: scanKey, spendKey: spendKey, network: network);
    }
    return null;
  }

  // ============================================
  // SECURE STORAGE (Keys)
  // ============================================

  Future<ApiScanKey?> readScanKey() async {
    final encoded = await secureStorage.read(key: _keyScanSk);
    if (encoded != null) {
      return ApiScanKey.decode(encoded: encoded);
    }
    return null;
  }

  Future<ApiSpendKey?> readSpendKey() async {
    final encoded = await secureStorage.read(key: _keySpendKey);
    if (encoded != null) {
      return ApiSpendKey.decode(encoded: encoded);
    }
    return null;
  }

  Future<String?> readSeedPhrase() async {
    return await secureStorage.read(key: _keySeedPhrase);
  }

  // ============================================
  // SHARED PREFERENCES (Simple values)
  // ============================================

  Future<ApiNetwork> readNetwork() async {
    final networkStr = await nonSecureStorage.getString(_keyNetwork);
    return ApiNetwork.values.byName(networkStr!);
  }

  Future<void> saveBirthday(DateTime birthday) async {
    await nonSecureStorage.setInt(_keyBirthday, birthday.toSeconds());
  }

  Future<DateTime?> readBirthday() async {
    final timestamp = await nonSecureStorage.getInt(_keyBirthday);
    return timestamp?.toDate();
  }

  Future<void> saveLastScan(int? lastScan) async {
    if (lastScan != null) {
      await nonSecureStorage.setInt(_keyLastScan, lastScan);
    } else {
      await nonSecureStorage.remove(_keyLastScan);
    }
  }

  Future<int?> readLastScan() async {
    final lastScan = await nonSecureStorage.getInt(_keyLastScan);
    return lastScan;
  }

  Future<void> saveDanaAddress(Bip353Address? danaAddress) async {
    if (danaAddress != null) {
      return await nonSecureStorage.setString(
          _keyDanaAddress, danaAddress.toString());
    } else {
      return await nonSecureStorage.remove(_keyDanaAddress);
    }
  }

  Future<Bip353Address?> readDanaAddress() async {
    final retrieved = await nonSecureStorage.getString(_keyDanaAddress);
    if (retrieved != null) {
      return Bip353Address.fromString(retrieved);
    }
    return null;
  }

  // ============================================
  // OWNED OUTPUTS - READ
  // ============================================

  /// Get total balance of unspent outputs in satoshis.
  Future<int> getUnspentBalance() async {
    final db = await _db;
    final result = await db.rawQuery('''
      SELECT COALESCE(SUM(amount_sat), 0) as total 
      FROM owned_outputs 
      WHERE spending_txid IS NULL AND mined_in_block IS NULL
    ''');
    return result.first['total'] as int;
  }

  /// Get all unspent outputs for spending.
  Future<Map<String, ApiDiscoveredOutput>> getUnspentOutputs() async {
    final db = await _db;
    final rows = await db.query(
      'owned_outputs',
      where: 'spending_txid IS NULL AND mined_in_block IS NULL',
    );

    final result = <String, ApiDiscoveredOutput>{};
    for (final row in rows) {
      final outpoint = '${row['txid']}:${row['vout']}';
      result[outpoint] = _rowToApiDiscoveredOutput(row);
    }
    return result;
  }

  /// Get outpoints that are not yet mined (for scanning).
  Future<List<String>> getNotMinedOutpoints() async {
    final db = await _db;
    final rows = await db.query(
      'owned_outputs',
      columns: ['txid', 'vout'],
      where: 'mined_in_block IS NULL',
    );

    return rows.map((row) => '${row['txid']}:${row['vout']}').toList();
  }

  /// Get amount for a specific outpoint.
  Future<int?> getOutputAmount(String txid, int vout) async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT amount_sat FROM owned_outputs 
      WHERE txid = ? AND vout = ?
    ''', [txid, vout]);

    if (rows.isEmpty) return null;
    return rows.first['amount_sat'] as int;
  }

  // ============================================
  // OWNED OUTPUTS - WRITE
  // ============================================

  /// Insert a new output (during scanning).
  Future<void> insertOutput({
    required String txid,
    required int vout,
    required int blockheight,
    required Uint8List tweak,
    required int amountSat,
    required String script,
    String? label,
  }) async {
    final db = await _db;
    await db.insert(
        'owned_outputs',
        {
          'txid': txid,
          'vout': vout,
          'blockheight': blockheight,
          'tweak': tweak,
          'amount_sat': amountSat,
          'script': script,
          'label': label,
          'spending_txid': null,
          'mined_in_block': null,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  /// Mark an output as spent (when user broadcasts a transaction).
  Future<void> markOutputSpent(String txid, int vout, String spendingTxid) async {
    final db = await _db;
    await db.update(
      'owned_outputs',
      {'spending_txid': spendingTxid},
      where: 'txid = ? AND vout = ?',
      whereArgs: [txid, vout],
    );
  }

  /// Mark an output as mined (during scanning).
  Future<void> markOutputMined(String txid, int vout, String minedInBlock,
      {String? spendingTxid}) async {
    final db = await _db;
    final updates = <String, Object?>{'mined_in_block': minedInBlock};
    if (spendingTxid != null) {
      updates['spending_txid'] = spendingTxid;
    }
    await db.update(
      'owned_outputs',
      updates,
      where: 'txid = ? AND vout = ?',
      whereArgs: [txid, vout],
    );
  }

  /// Delete outputs above a certain blockheight (for resetToHeight).
  Future<void> deleteOutputsAboveHeight(int height) async {
    final db = await _db;
    await db.delete(
      'owned_outputs',
      where: 'blockheight > ?',
      whereArgs: [height],
    );
  }

  // ============================================
  // TRANSACTION HISTORY - READ
  // ============================================

  /// Get all transactions for UI display.
  Future<List<ApiRecordedTransaction>> getAllTransactions() async {
    final db = await _db;

    // Get all incoming transactions
    final incomingRows = await db.query(
      'tx_incoming',
      orderBy: 'COALESCE(confirmation_height, 9999999999) DESC, created_at DESC',
    );

    // Get all outgoing transactions
    final outgoingRows = await db.query(
      'tx_outgoing',
      orderBy: 'COALESCE(confirmation_height, 9999999999) DESC, created_at DESC',
    );

    final result = <ApiRecordedTransaction>[];

    // Process incoming transactions
    for (final row in incomingRows) {
      final txid = row['txid'] as String;

      result.add(ApiRecordedTransaction.incoming(
        ApiRecordedTransactionIncoming(
          txid: txid,
          amount: ApiAmount(
              field0: BigInt.from(row['amount_received_sat'] as int)),
          confirmationHeight: row['confirmation_height'] as int?,
          confirmationBlockhash: row['confirmation_blockhash'] as String?,
        ),
      ));
    }

    // Process outgoing transactions
    for (final row in outgoingRows) {
      final txid = row['txid'] as String;

      // Fetch spent outpoints
      final spentRows = await db.query(
        'tx_spent_outpoints',
        where: 'txid = ?',
        whereArgs: [txid],
      );
      final spentOutpoints = spentRows
          .map((r) => '${r['outpoint_txid']}:${r['outpoint_vout']}')
          .toList();

      // Fetch recipients
      final recipientRows = await db.query(
        'tx_recipients',
        where: 'txid = ?',
        whereArgs: [txid],
      );
      final recipients = recipientRows
          .map((r) => ApiRecipient(
                address: r['address'] as String,
                amount: ApiAmount(field0: BigInt.from(r['amount_sat'] as int)),
              ))
          .toList();

      result.add(ApiRecordedTransaction.outgoing(
        ApiRecordedTransactionOutgoing(
          txid: txid,
          spentOutpoints: spentOutpoints,
          recipients: recipients,
          confirmationHeight: row['confirmation_height'] as int?,
          confirmationBlockhash: row['confirmation_blockhash'] as String?,
          change: ApiAmount(field0: BigInt.from(row['change_sat'] as int? ?? 0)),
          fee: ApiAmount(field0: BigInt.from(row['fee_sat'] as int? ?? 0)),
        ),
      ));
    }

    // Sort by confirmation height (most recent first)
    result.sort((a, b) {
      int getConfirmationHeight(ApiRecordedTransaction tx) {
        return switch (tx) {
          ApiRecordedTransaction_Incoming(:final field0) =>
            field0.confirmationHeight ?? 9999999999,
          ApiRecordedTransaction_Outgoing(:final field0) =>
            field0.confirmationHeight ?? 9999999999,
          ApiRecordedTransaction_UnknownOutgoing(:final field0) =>
            field0.confirmationHeight,
        };
      }

      final aHeight = getConfirmationHeight(a);
      final bHeight = getConfirmationHeight(b);
      return bHeight.compareTo(aHeight);
    });

    return result;
  }

  /// Get sum of unconfirmed change from outgoing transactions.
  Future<int> getUnconfirmedChange() async {
    final db = await _db;
    final result = await db.rawQuery('''
      SELECT COALESCE(SUM(change_sat), 0) as total 
      FROM tx_outgoing 
      WHERE confirmation_height IS NULL
    ''');
    return result.first['total'] as int;
  }

  /// Check if a txid is from an outgoing transaction we sent (self-send check).
  Future<bool> isOwnOutgoingTx(String txid) async {
    final db = await _db;
    final result = await db.rawQuery('''
      SELECT 1 FROM tx_outgoing 
      WHERE txid = ?
      LIMIT 1
    ''', [txid]);
    return result.isNotEmpty;
  }

  // ============================================
  // TRANSACTION HISTORY - WRITE
  // ============================================

  /// Add an incoming transaction.
  Future<void> addIncomingTransaction({
    required String txid,
    required int amountSat,
    required int confirmationHeight,
    required String confirmationBlockhash,
  }) async {
    final db = await _db;
    await db.insert(
      'tx_incoming',
      {
        'txid': txid,
        'amount_received_sat': amountSat,
        'confirmation_height': confirmationHeight,
        'confirmation_blockhash': confirmationBlockhash,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Add an outgoing transaction (when user sends).
  Future<void> addOutgoingTransaction({
    required String txid,
    required List<(String, int, int)> spentOutpoints, // (txid, vout, amount)
    required List<ApiRecipient> recipients,
    required int changeSat,
    required int feeSat,
  }) async {
    final db = await _db;

    await db.transaction((txn) async {
      final totalAmount =
          recipients.fold<int>(0, (sum, r) => sum + r.amount.field0.toInt());

      await txn.insert(
        'tx_outgoing',
        {
          'txid': txid,
          'amount_spent_sat': totalAmount + feeSat + changeSat,
          'confirmation_height': null,
          'confirmation_blockhash': null,
          'change_sat': changeSat,
          'fee_sat': feeSat,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      for (final (outTxid, outVout, _) in spentOutpoints) {
        await txn.insert('tx_spent_outpoints', {
          'txid': txid,
          'outpoint_txid': outTxid,
          'outpoint_vout': outVout,
        });
      }

      for (final recipient in recipients) {
        await txn.insert('tx_recipients', {
          'txid': txid,
          'address': recipient.address,
          'amount_sat': recipient.amount.field0.toInt(),
        });
      }
    });
  }

  /// Mark outputs as spent without creating history entry (unknown spend case).
  /// Used when outputs are spent from another device/wallet.
  Future<void> markOutputsSpentUnknown({
    required List<(String, int, int)> spentOutpoints, // (txid, vout, amount)
    required String minedInBlock,
  }) async {
    final db = await _db;

    await db.transaction((txn) async {
      for (final (outTxid, outVout, _) in spentOutpoints) {
        await txn.update(
          'owned_outputs',
          {
            'spending_txid': null, // Unknown txid
            'mined_in_block': minedInBlock,
          },
          where: 'txid = ? AND vout = ?',
          whereArgs: [outTxid, outVout],
        );
      }
    });
  }

  /// Confirm an outgoing transaction (during scan when we see it mined).
  Future<bool> confirmOutgoingTransaction({
    required String spentOutpointTxid,
    required int spentOutpointVout,
    required int confirmationHeight,
    required String confirmationBlockhash,
  }) async {
    final db = await _db;

    final result = await db.rawQuery('''
      SELECT h.txid 
      FROM tx_outgoing h
      JOIN tx_spent_outpoints s ON s.txid = h.txid
      WHERE s.outpoint_txid = ? 
        AND s.outpoint_vout = ?
      LIMIT 1
    ''', [spentOutpointTxid, spentOutpointVout]);

    if (result.isEmpty) {
      return false; // No matching outgoing transaction found
    }

    final txid = result.first['txid'] as String;
    await db.update(
      'tx_outgoing',
      {
        'confirmation_height': confirmationHeight,
        'confirmation_blockhash': confirmationBlockhash,
      },
      where: 'txid = ?',
      whereArgs: [txid],
    );

    return true;
  }

  /// Delete transactions above a certain blockheight (for resetToHeight).
  Future<void> deleteTransactionsAboveHeight(int height) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete(
        'tx_incoming',
        where: 'confirmation_height IS NOT NULL AND confirmation_height > ?',
        whereArgs: [height],
      );
      await txn.delete(
        'tx_outgoing',
        where: 'confirmation_height IS NOT NULL AND confirmation_height > ?',
        whereArgs: [height],
      );
    });
  }

  /// Reset wallet data to a specific height.
  Future<void> resetToHeight(int height) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete(
        'owned_outputs',
        where: 'blockheight > ?',
        whereArgs: [height],
      );

      await txn.delete(
        'tx_incoming',
        where: 'confirmation_height IS NOT NULL AND confirmation_height > ?',
        whereArgs: [height],
      );
      await txn.delete(
        'tx_outgoing',
        where: 'confirmation_height IS NOT NULL AND confirmation_height > ?',
        whereArgs: [height],
      );
    });

    await saveLastScan(height);
  }

  // ============================================
  // HELPER METHODS
  // ============================================

  (String, int) _parseOutpoint(String outpoint) {
    final parts = outpoint.split(':');
    return (parts[0], int.parse(parts[1]));
  }

  ApiDiscoveredOutput _rowToApiDiscoveredOutput(Map<String, Object?> row) {
    return ApiDiscoveredOutput(
      tweak: U8Array32(row['tweak'] as Uint8List),
      value: ApiAmount(field0: BigInt.from(row['amount_sat'] as int)),
      scriptPubkey: row['script'] as String,
      label: row['label'] as String?,
    );
  }

  Future<void> _insertTransactionInTxn(
      Transaction txn, ApiRecordedTransaction tx) async {
    switch (tx) {
      case ApiRecordedTransaction_Incoming(:final field0):
        await txn.insert('tx_incoming', {
          'txid': field0.txid,
          'amount_received_sat': field0.amount.field0.toInt(),
          'confirmation_height': field0.confirmationHeight,
          'confirmation_blockhash': field0.confirmationBlockhash,
        });
        break;

      case ApiRecordedTransaction_Outgoing(:final field0):
        final totalAmount = field0.recipients
            .fold<int>(0, (sum, r) => sum + r.amount.field0.toInt());

        await txn.insert('tx_outgoing', {
          'txid': field0.txid,
          'amount_spent_sat': totalAmount + field0.fee.field0.toInt(),
          'confirmation_height': field0.confirmationHeight?.toInt(),
          'confirmation_blockhash': field0.confirmationBlockhash?.toString(),
          'change_sat': field0.change.field0.toInt(),
          'fee_sat': field0.fee.field0.toInt(),
        });

        for (final outpoint in field0.spentOutpoints) {
          final (outTxid, outVout) = _parseOutpoint(outpoint);
          await txn.insert('tx_spent_outpoints', {
            'txid': field0.txid,
            'outpoint_txid': outTxid,
            'outpoint_vout': outVout,
          });
        }

        for (final recipient in field0.recipients) {
          await txn.insert('tx_recipients', {
            'txid': field0.txid,
            'address': recipient.address,
            'amount_sat': recipient.amount.field0.toInt(),
          });
        }
        break;

      case ApiRecordedTransaction_UnknownOutgoing(:final field0):
        // Don't create history entry for unknown outgoing
        // Just mark the outputs as spent with unknown txid
        for (final outpoint in field0.spentOutpoints) {
          final (outTxid, outVout) = _parseOutpoint(outpoint);
          await txn.update(
            'owned_outputs',
            {
              'spending_txid': null,
              'mined_in_block': field0.confirmationBlockhash,
            },
            where: 'txid = ? AND vout = ?',
            whereArgs: [outTxid, outVout],
          );
        }
        break;
    }
  }

  // ============================================
  // BACKUP & RESTORE
  // ============================================

  /// Gather wallet data from Secure Storage & SharedPreferences.
  Future<WalletBackup> createWalletBackup() async {
    final scanKeyEncoded = await secureStorage.read(key: _keyScanSk);
    final spendKeyEncoded = await secureStorage.read(key: _keySpendKey);
    final seedPhrase = await readSeedPhrase();
    final birthday = await readBirthday();
    final lastScan = await readLastScan();
    final network = await readNetwork();
    final danaAddress = await readDanaAddress();

    return WalletBackup(
      scanKey: scanKeyEncoded!,
      spendKey: spendKeyEncoded!,
      seedPhrase: seedPhrase,
      birthday: birthday?.toSeconds(),
      network: network.name,
      lastScan: lastScan,
      danaAddress: danaAddress?.toString(),
    );
  }

  /// Gather all transaction data from SQLite (outputs + transaction history).
  Future<TransactionDataBackup> createTransactionDataBackup() async {
    final db = await _db;

    // Owned outputs — raw rows, no conversion to Api types
    final outputRows = await db.query('owned_outputs');
    final outputs =
        outputRows.map((row) => OwnedOutputBackup.fromRow(row)).toList();

    // Incoming transactions
    final incomingRows = await db.query('tx_incoming');
    final incoming =
        incomingRows.map((row) => IncomingTxBackup.fromRow(row)).toList();

    // Outgoing transactions with their spent outpoints and recipients
    final outgoingRows = await db.query('tx_outgoing');
    final outgoing = <OutgoingTxBackup>[];

    for (final row in outgoingRows) {
      final txid = row['txid'] as String;

      final spentRows = await db.query(
        'tx_spent_outpoints',
        where: 'txid = ?',
        whereArgs: [txid],
      );
      final spentOutpoints = spentRows
          .map((r) => '${r['outpoint_txid']}:${r['outpoint_vout']}')
          .toList();

      final recipientRows = await db.query(
        'tx_recipients',
        where: 'txid = ?',
        whereArgs: [txid],
      );
      final recipients = recipientRows
          .map((r) => RecipientBackup(
                address: r['address'] as String,
                amountSat: r['amount_sat'] as int,
              ))
          .toList();

      outgoing.add(OutgoingTxBackup(
        txid: txid,
        amountSpentSat: row['amount_spent_sat'] as int,
        changeSat: row['change_sat'] as int? ?? 0,
        feeSat: row['fee_sat'] as int? ?? 0,
        confirmationHeight: row['confirmation_height'] as int?,
        confirmationBlockhash: row['confirmation_blockhash'] as String?,
        userNote: row['user_note'] as String?,
        spentOutpoints: spentOutpoints,
        recipients: recipients,
      ));
    }

    return TransactionDataBackup(
      ownedOutputs: outputs,
      incomingTransactions: incoming,
      outgoingTransactions: outgoing,
    );
  }

  /// Restore wallet to Secure Storage & SharedPreferences.
  Future<void> restoreWallet(WalletBackup wallet) async {
    await reset();

    await secureStorage.write(key: _keyScanSk, value: wallet.scanKey);
    await secureStorage.write(key: _keySpendKey, value: wallet.spendKey);
    if (wallet.birthday != null) {
      await nonSecureStorage.setInt(_keyBirthday, wallet.birthday!);
    }
    await nonSecureStorage.setString(_keyNetwork, wallet.network);

    if (wallet.seedPhrase != null) {
      await secureStorage.write(
          key: _keySeedPhrase, value: wallet.seedPhrase);
    }

    await saveLastScan(wallet.lastScan);

    if (wallet.danaAddress != null) {
      await saveDanaAddress(Bip353Address.fromString(wallet.danaAddress!));
    }
  }

  /// Restore all transaction data into SQLite (outputs + transaction history).
  Future<void> restoreTransactionData(TransactionDataBackup data) async {
    final db = await _db;

    await db.transaction((txn) async {
      // Restore owned outputs
      for (final output in data.ownedOutputs) {
        await txn.insert(
          'owned_outputs',
          output.toRow(),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }

      // Restore incoming transactions
      for (final tx in data.incomingTransactions) {
        await txn.insert(
          'tx_incoming',
          tx.toRow(),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }

      // Restore outgoing transactions with spent outpoints and recipients
      for (final tx in data.outgoingTransactions) {
        await txn.insert(
          'tx_outgoing',
          {
            'txid': tx.txid,
            'amount_spent_sat': tx.amountSpentSat,
            'change_sat': tx.changeSat,
            'fee_sat': tx.feeSat,
            'confirmation_height': tx.confirmationHeight,
            'confirmation_blockhash': tx.confirmationBlockhash,
            'user_note': tx.userNote,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );

        for (final outpoint in tx.spentOutpoints) {
          final parts = outpoint.split(':');
          await txn.insert(
            'tx_spent_outpoints',
            {
              'txid': tx.txid,
              'outpoint_txid': parts[0],
              'outpoint_vout': int.parse(parts[1]),
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }

        for (final recipient in tx.recipients) {
          await txn.insert(
            'tx_recipients',
            {
              'txid': tx.txid,
              'address': recipient.address,
              'amount_sat': recipient.amountSat,
            },
          );
        }
      }
    });
  }
}
