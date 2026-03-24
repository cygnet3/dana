import 'dart:convert';
import 'dart:typed_data';

import 'package:danawallet/data/models/bip353_address.dart';
import 'package:danawallet/extensions/date_time.dart';
import 'package:danawallet/generated/rust/api/backup.dart';
import 'package:danawallet/generated/rust/api/history.dart';
import 'package:danawallet/generated/rust/api/structs/network.dart';
import 'package:danawallet/generated/rust/api/structs/recorded_transaction.dart';
import 'package:danawallet/generated/rust/api/wallet.dart';
import 'package:danawallet/generated/rust/api/wallet/setup.dart';
import 'package:danawallet/repositories/database_helper.dart';
import 'package:danawallet/repositories/owned_outputs_repository.dart';
import 'package:danawallet/repositories/tx_history_repository.dart';
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
const String _keyLastSync = "lastscan";
const String _keyDanaAddress = "danaaddress";

class WalletRepository {
  final secureStorage = const FlutterSecureStorage();
  final nonSecureStorage = SharedPreferencesAsync();

  // private constructor
  WalletRepository._();

  // singleton class
  static final instance = WalletRepository._();

  Future<Database> get _db async => await DatabaseHelper.instance.database;

  /// Converts a [BigInt] satoshi amount to [int] for SQLite storage.
  /// Only kept here for use in the legacy migration helper [_insertTransactionInTxn].
  static int _bigIntToSat(BigInt value) {
    if (!value.isValidInt) {
      throw StateError('Amount overflows int: $value');
    }
    return value.toInt();
  }

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

  Future<void> reset() async {
    // delete secure storage
    await secureStorage.deleteAll();

    // delete non secure storage
    await nonSecureStorage.clear(allowList: {
      _keyNetwork,
      _keyTxHistory,
      _keyLastSync,
      _keyOwnedOutputs,
      _keyBirthday,
      _keyDanaAddress,
    });

    // clear SQLite wallet data
    await OwnedOutputsRepository.instance.reset();
    await TxHistoryRepository.instance.reset();
  }

  Future<SpWallet> setupWallet(WalletSetupResult walletSetup,
      ApiNetwork network, DateTime? birthday, int? lastSync) async {
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
    await saveLastSync(lastSync);

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
    } else {
      return null;
    }
  }

  Future<ApiScanKey?> readScanKey() async {
    final encoded = await secureStorage.read(key: _keyScanSk);
    if (encoded != null) {
      return ApiScanKey.decode(encoded: encoded);
    } else {
      return null;
    }
  }

  Future<ApiSpendKey?> readSpendKey() async {
    final encoded = await secureStorage.read(key: _keySpendKey);
    if (encoded != null) {
      return ApiSpendKey.decode(encoded: encoded);
    } else {
      return null;
    }
  }

  Future<String?> readSeedPhrase() async {
    return await secureStorage.read(key: _keySeedPhrase);
  }

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

  Future<void> saveLastSync(int? lastSync) async {
    if (lastSync != null) {
      await nonSecureStorage.setInt(_keyLastSync, lastSync);
    } else {
      await nonSecureStorage.remove(_keyLastSync);
    }
  }

  Future<int?> readLastSync() async {
    final lastSync = await nonSecureStorage.getInt(_keyLastSync);
    return lastSync;
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
    } else {
      return null;
    }
  }

  /// Reset wallet data to a specific height.
  Future<void> resetToHeight(int height) async {
    await OwnedOutputsRepository.instance.deleteOutputsAboveHeight(height);
    await TxHistoryRepository.instance.deleteTransactionsAboveHeight(height);
    await saveLastSync(height);
  }

  Future<WalletBackup> createWalletBackup() async {
    final wallet = await readWallet();
    final birthday = await readBirthday();
    final seedPhrase = await readSeedPhrase();
    final lastSync = await readLastSync();
    final network = await readNetwork();

    // LEGACY: TxHistory is deprecated — wallet recovery relies on seed phrase (rescan from birthday).
    // TxHistory.empty() is only used here for backup compatibility.
    // TODO: Remove TxHistory from backup format entirely.
    final history = TxHistory.empty();

    return WalletBackup(
        wallet: wallet!,
        birthday: birthday?.toSeconds(),
        lastScan: lastSync!,
        txHistory: history,
        seedPhrase: seedPhrase,
        network: network);
  }

  Future<void> restoreWalletBackup(WalletBackup backup) async {
    await reset();

    await secureStorage.write(key: _keyScanSk, value: backup.scanKey.encode());
    await secureStorage.write(
        key: _keySpendKey, value: backup.spendKey.encode());
    await nonSecureStorage.setString(_keyNetwork, backup.network.name);

    if (backup.birthday != null) {
      await nonSecureStorage.setInt(_keyBirthday, backup.birthday!);
    }

    if (backup.seedPhrase != null) {
      await secureStorage.write(key: _keySeedPhrase, value: backup.seedPhrase);
    }

    await saveLastSync(backup.lastScan); 
  }

  (String, int) _parseOutpoint(String outpoint) {
    final parts = outpoint.split(':');
    return (parts[0], int.parse(parts[1]));
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
            'amount_sat': _bigIntToSat(recipient.amount.field0),
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
}
