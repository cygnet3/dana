import 'package:danawallet/data/models/bip353_address.dart';
import 'package:danawallet/extensions/date_time.dart';
import 'package:danawallet/generated/rust/api/backup.dart';
import 'package:danawallet/generated/rust/api/history.dart';
import 'package:danawallet/generated/rust/api/outputs.dart';
import 'package:danawallet/generated/rust/api/structs/network.dart';
import 'package:danawallet/generated/rust/api/wallet.dart';
import 'package:danawallet/generated/rust/api/wallet/setup.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

// secure storage
const String _keyScanSk = "scansk";
const String _keySpendKey = "spendkey";
const String _keySeedPhrase = "seedphrase";

// non secure storage
// this will likely replaced by an sql database in the future
const String _keyBirthday = "birthday";
const String _keyNetwork = "network";
const String _keyTxHistory = "txhistory";
const String _keyOwnedOutputs = "ownedoutputs";
const String _keyLastScan = "lastscan";
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
      _keyTxHistory,
      _keyLastScan,
      _keyOwnedOutputs,
      _keyBirthday,
      _keyDanaAddress,
    });
  }

  Future<SpWallet> setupWallet(
      WalletSetupResult walletSetup, ApiNetwork network, DateTime birthday) async {
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
    await nonSecureStorage.setInt(_keyBirthday, birthday.toSeconds());
    await nonSecureStorage.setString(_keyNetwork, network.name);

    if (seedPhrase != null) {
      await secureStorage.write(key: _keySeedPhrase, value: seedPhrase);
    }

    // set default values for new wallet
    await saveLastScan(birthday);
    await saveHistory(TxHistory.empty());
    await saveOwnedOutputs(OwnedOutputs.empty());

    // check if creation was successful by reading wallet
    final wallet = await readWallet();
    return wallet!;
  }

  Future<SpWallet?> readWallet() async {
    // read scan and spend key. if these are present, the entire wallet should be present
    final scanKey = await readScanKey();
    final spendKey = await readSpendKey();

    if (scanKey != null && spendKey != null) {
      // if the scan and spend keys are present, then network should also be present
      // network is required, since we need it to generate the receive & change payment codes
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

  Future<void> saveHistory(TxHistory history) async {
    return await nonSecureStorage.setString(_keyTxHistory, history.encode());
  }

  Future<TxHistory> readHistory() async {
    final encodedHistory = await nonSecureStorage.getString(_keyTxHistory);
    return TxHistory.decode(encodedHistory: encodedHistory!);
  }

  Future<void> saveBirthday(DateTime birthday) async {
    await nonSecureStorage.setInt(_keyBirthday, birthday.toSeconds());
  }

  Future<DateTime> readBirthday() async {
    final timestamp = await nonSecureStorage.getInt(_keyBirthday);
    return timestamp!.toDate();
  }

  Future<void> saveLastScan(int lastScan) async {
    await nonSecureStorage.setInt(_keyLastScan, lastScan);
  }

  Future<int> readLastScan() async {
    final lastScan = await nonSecureStorage.getInt(_keyLastScan);
    return lastScan!;
  }

  Future<void> saveOwnedOutputs(OwnedOutputs ownedOutputs) async {
    await nonSecureStorage.setString(_keyOwnedOutputs, ownedOutputs.encode());
  }

  Future<OwnedOutputs> readOwnedOutputs() async {
    final encodedOutputs = await nonSecureStorage.getString(_keyOwnedOutputs);
    return OwnedOutputs.decode(encodedOutputs: encodedOutputs!);
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

  Future<WalletBackup> createWalletBackup() async {
    final wallet = await readWallet();
    final birthday = await readBirthday();
    final history = await readHistory();
    final outputs = await readOwnedOutputs();
    final seedPhrase = await readSeedPhrase();
    final lastScan = await readLastScan();
    final network = await readNetwork();

    return WalletBackup(
        wallet: wallet!,
        birthday: birthday.toSeconds(),
        lastScan: lastScan,
        txHistory: history,
        ownedOutputs: outputs,
        seedPhrase: seedPhrase,
        network: network);
  }

  Future<void> restoreWalletBackup(WalletBackup backup) async {
    await reset();

    // insert new values
    await secureStorage.write(key: _keyScanSk, value: backup.scanKey.encode());
    await secureStorage.write(
        key: _keySpendKey, value: backup.spendKey.encode());
    await nonSecureStorage.setInt(_keyBirthday, backup.birthday);
    await nonSecureStorage.setString(_keyNetwork, backup.network.name);

    if (backup.seedPhrase != null) {
      await secureStorage.write(key: _keySeedPhrase, value: backup.seedPhrase);
    }

    await saveHistory(backup.txHistory);
    await saveOwnedOutputs(backup.ownedOutputs);
    await saveLastScan(backup.lastScan);
  }
}
