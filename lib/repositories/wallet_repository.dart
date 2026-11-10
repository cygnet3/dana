import 'dart:convert';

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
// frigate scan-session state (D2): single-writer (only the isolate running
// the scan writes it); lives and dies with the wallet via the reset()
// allowList below. No caught-up flag is persisted — catch-up is derived
// from the keyless tip probe at every wake.
const String _keyFrigateScanActive = "frigateScanActive";
const String _keyFrigateScanPid = "frigateScanPid";
const String _keyFrigateScanBeat = "frigateScanBeat";
const String _keyFrigateLastTipHeight = "frigateLastTipHeight";
const String _keyFrigateLastTipHash = "frigateLastTipHash";
// D6/D7 per-wallet frigate disclosure state: the public warning fires exactly
// once per wallet lifetime, and every subscribe appends an append-only
// {url, visibility, date} record. Both live and die with the wallet via the
// reset() allowList below.
const String _keyFrigatePublicWarned = "frigatePublicWarned";
const String _keyFrigateDisclosure = "frigateDisclosureRecords";

/// Storage surface [SyncEngine] needs from [WalletRepository]; lets tests
/// substitute an in-memory store.
abstract class WalletStore {
  Future<bool> hasWallet();
  Future<SpWallet?> readWallet();
  Future<Network> readNetwork();
  Future<int?> readLastSync();
  Future<void> saveLastSync(int? lastSync);
  Future<DateTime?> readBirthday();
  Future<void> beginFrigateScan({required int pid});
  Future<void> touchFrigateScanBeat();
  Future<void> endFrigateScan({int? tipHeight, String? tipHash});
  Future<FrigateScanLock?> readFrigateScanLock();
  Future<void> appendFrigateDisclosureRecord({
    required String url,
    required String visibility,
  });
}

class WalletRepository implements WalletStore {
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
      _keyFrigateScanActive,
      _keyFrigateScanPid,
      _keyFrigateScanBeat,
      _keyFrigateLastTipHeight,
      _keyFrigateLastTipHash,
      _keyFrigatePublicWarned,
      _keyFrigateDisclosure,
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

  @override
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

  @override
  Future<Network> readNetwork() async {
    final networkStr = await nonSecureStorage.getString(_keyNetwork);
    return Network.values.byName(networkStr!);
  }

  Future<void> saveBirthday(DateTime birthday) async {
    await nonSecureStorage.setInt(_keyBirthday, birthday.toSeconds());
  }

  @override
  Future<DateTime?> readBirthday() async {
    final timestamp = await nonSecureStorage.getInt(_keyBirthday);
    return timestamp?.toDate();
  }

  @override
  Future<void> saveLastSync(int? lastSync) async {
    if (lastSync != null) {
      await nonSecureStorage.setInt(_keyLastSync, lastSync);
    } else {
      await nonSecureStorage.remove(_keyLastSync);
    }
  }

  @override
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

  /// Marks a frigate scan as running in [pid] (single-writer: call only from
  /// the isolate that will run the scan).
  @override
  Future<void> beginFrigateScan({required int pid}) async {
    await nonSecureStorage.setBool(_keyFrigateScanActive, true);
    await nonSecureStorage.setInt(_keyFrigateScanPid, pid);
    await touchFrigateScanBeat();
  }

  /// Refreshes the scan heartbeat so another wake can tell a live scan from
  /// a dead lock.
  @override
  Future<void> touchFrigateScanBeat() async {
    await nonSecureStorage.setInt(
        _keyFrigateScanBeat, DateTime.now().millisecondsSinceEpoch);
  }

  /// Records the last tip pair (diagnostics + the D9 "last Confirmed
  /// boundary" record) and clears the scan lock. Safe to call with no scan
  /// running.
  @override
  Future<void> endFrigateScan({int? tipHeight, String? tipHash}) async {
    if (tipHeight != null) {
      await nonSecureStorage.setInt(_keyFrigateLastTipHeight, tipHeight);
    }
    if (tipHash != null) {
      await nonSecureStorage.setString(_keyFrigateLastTipHash, tipHash);
    }
    await nonSecureStorage.remove(_keyFrigateScanActive);
    await nonSecureStorage.remove(_keyFrigateScanPid);
    await nonSecureStorage.remove(_keyFrigateScanBeat);
  }

  @override
  Future<FrigateScanLock?> readFrigateScanLock() async {
    final active = await nonSecureStorage.getBool(_keyFrigateScanActive);
    final pid = await nonSecureStorage.getInt(_keyFrigateScanPid);
    final beatMs = await nonSecureStorage.getInt(_keyFrigateScanBeat);
    if (active != true || pid == null || beatMs == null) {
      return null;
    }
    return FrigateScanLock(
        pid: pid, beat: DateTime.fromMillisecondsSinceEpoch(beatMs));
  }

  /// True when both key halves exist in secure storage (same condition
  /// [readWallet] uses to return a wallet).
  @override
  Future<bool> hasWallet() async {
    final scanKey = await secureStorage.read(key: _keyScanSk);
    final spendKey = await secureStorage.read(key: _keySpendKey);
    return scanKey != null && spendKey != null;
  }

  /// Whether the one-time public-instance warning (D6) already fired for
  /// this wallet. Per-wallet by construction: the key is cleared by
  /// reset() and never by the settings UI.
  Future<bool> readFrigatePublicWarned() async {
    return await nonSecureStorage.getBool(_keyFrigatePublicWarned) ?? false;
  }

  /// Marks the D6 public warning as fired — exactly once per wallet.
  Future<void> markFrigatePublicWarned() async {
    await nonSecureStorage.setBool(_keyFrigatePublicWarned, true);
  }

  /// The wallet's append-only frigate disclosure records (D7):
  /// `{url, visibility, date}` entries, oldest first. The list never drives
  /// a dialog — only [readFrigatePublicWarned] gates the one-time warning.
  Future<List<Map<String, String>>> readFrigateDisclosureRecords() async {
    final raw = await nonSecureStorage.getString(_keyFrigateDisclosure);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map(
            (entry) => Map<String, String>.from(entry as Map<dynamic, dynamic>))
        .toList();
  }

  /// Appends one disclosure record (D7). Append-only: entries are never
  /// removed or rewritten within a wallet lifetime (reset() clears the key
  /// only when the wallet itself is wiped).
  @override
  Future<void> appendFrigateDisclosureRecord({
    required String url,
    required String visibility,
  }) async {
    final records = await readFrigateDisclosureRecords();
    records.add({
      'url': url,
      'visibility': visibility,
      'date': DateTime.now().toUtc().toIso8601String(),
    });
    await nonSecureStorage.setString(
        _keyFrigateDisclosure, jsonEncode(records));
  }
}

/// Liveness record of a running frigate scan (D2).
class FrigateScanLock {
  final int pid;
  final DateTime beat;

  FrigateScanLock({required this.pid, required this.beat});

  /// Dead if written by another process (pid no longer ours), or if the
  /// heartbeat is older than 15 minutes (covers pid reuse).
  bool isStale(
          {required int currentPid,
          Duration maxAge = const Duration(minutes: 15)}) =>
      pid != currentPid || DateTime.now().difference(beat) > maxAge;
}
