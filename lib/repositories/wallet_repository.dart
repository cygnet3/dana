import 'package:danawallet/data/models/bip353_address.dart';
import 'package:danawallet/data/models/dana_backup.dart';
import 'package:danawallet/extensions/date_time.dart';
import 'package:danawallet/generated/rust/api/structs/network.dart';
import 'package:danawallet/generated/rust/api/structs/recorded_transaction.dart';
import 'package:danawallet/generated/rust/api/wallet.dart';
import 'package:danawallet/generated/rust/api/wallet/setup.dart';
import 'package:danawallet/repositories/database_helper.dart';
import 'package:danawallet/repositories/owned_outputs_repository.dart';
import 'package:danawallet/repositories/tx_history_repository.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

// secure storage
const String _keyScanSk = "scansk";
const String _keySpendKey = "spendkey";
const String _keySeedPhrase = "seedphrase";

// non secure storage (SharedPreferences)
const String _keyBirthday = "birthday";
const String _keyNetwork = "network";
const String _keyLastSync = "lastscan";
const String _keyDanaAddress = "danaaddress";

class WalletRepository {
  final secureStorage = const FlutterSecureStorage();
  final nonSecureStorage = SharedPreferencesAsync();

  // private constructor
  WalletRepository._();

  // singleton class
  static final instance = WalletRepository._();

  Future<void> reset() async {
    // delete secure storage
    await secureStorage.deleteAll();

    // delete non secure storage
    await nonSecureStorage.clear(allowList: {
      _keyNetwork,
      _keyLastSync,
      _keyBirthday,
      _keyDanaAddress,
    });
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
    await saveLastSync(height);
  }

  Future<WalletBackup> createWalletBackup() async {
    final scanKeyEncoded = await secureStorage.read(key: _keyScanSk);
    final spendKeyEncoded = await secureStorage.read(key: _keySpendKey);
    final seedPhrase = await readSeedPhrase();
    final birthday = await readBirthday();
    final lastSync = await readLastSync();
    final network = await readNetwork();
    final danaAddress = await readDanaAddress();

    return WalletBackup(
      scanKey: scanKeyEncoded!,
      spendKey: spendKeyEncoded!,
      seedPhrase: seedPhrase,
      birthday: birthday?.toSeconds(),
      network: network.name,
      lastSync: lastSync,
      danaAddress: danaAddress?.toString(),
    );
  }

  /// Gather all transaction data from SQLite (outputs + transaction history).
  Future<TransactionDataBackup> createTransactionDataBackup() async {
    final allOwnedOutputs =
        await OwnedOutputsRepository.instance.getAllOwnedOutputs();
    final ownedOutputsBackup =
        allOwnedOutputs.map(OwnedOutputBackup.fromOwnedOutput).toList();

    final allTransactions =
        await TxHistoryRepository.instance.getAllTransactions();

    final incoming = <IncomingTxBackup>[];
    final outgoing = <OutgoingTxBackup>[];

    for (final tx in allTransactions) {
      switch (tx) {
        case ApiRecordedTransaction_Incoming(:final field0):
          incoming.add(IncomingTxBackup.fromApiIncoming(field0));
        case ApiRecordedTransaction_Outgoing(:final field0):
          outgoing.add(OutgoingTxBackup.fromApiOutgoing(field0));
        case ApiRecordedTransaction_UnknownOutgoing():
          // Unknown outgoing transactions have no txid and are not recorded in
          // tx history, so they cannot be backed up as outgoing entries.
          // The associated owned_outputs rows (with mined_in_block set) are
          // captured in ownedOutputsBackup above.
          break;
      }
    }

    return TransactionDataBackup(
      ownedOutputs: ownedOutputsBackup,
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

    await saveLastSync(wallet.lastSync);

    if (wallet.danaAddress != null) {
      await saveDanaAddress(Bip353Address.fromString(wallet.danaAddress!));
    }
  }

  /// Restore all transaction data into SQLite (outputs + transaction history).
  Future<void> restoreTransactionData(TransactionDataBackup data) async {
    final db = await DatabaseHelper.instance.database;

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
