import 'package:danawallet/data/models/bip353_address.dart';
import 'package:danawallet/extensions/date_time.dart';
import 'package:danawallet/generated/rust/api/structs/network.dart';
import 'package:danawallet/generated/rust/api/wallet.dart';
import 'package:danawallet/generated/rust/api/wallet/setup.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  Future<SpWallet> setupWallet(WalletSetupResult walletSetup, Network network,
      DateTime? birthday, int? lastSync) async {
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

  Future<Network> readNetwork() async {
    final networkStr = await nonSecureStorage.getString(_keyNetwork);
    return Network.values.byName(networkStr!);
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
}
