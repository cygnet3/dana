import 'dart:async';

import 'package:danawallet/constants.dart';
import 'package:danawallet/extensions/date_time.dart';
import 'package:danawallet/extensions/network.dart';
import 'package:danawallet/generated/rust/api/chain.dart';
import 'package:danawallet/generated/rust/api/stream.dart';
import 'package:danawallet/generated/rust/api/structs/state_update.dart';
import 'package:danawallet/repositories/mempool_api_repository.dart';
import 'package:danawallet/repositories/owned_outputs_repository.dart';
import 'package:danawallet/repositories/settings_repository.dart';
import 'package:danawallet/repositories/transactions_repository.dart';
import 'package:danawallet/repositories/wallet_repository.dart';
import 'package:logger/logger.dart';

/// Platform-agnostic sync core.
///
/// Owns the [createSyncResultStream] subscription and the [trySync] logic.
/// All platform-specific side effects (IPC messages, progress bar updates,
/// UI state refreshes) are injected as callbacks so this class stays free of
/// Flutter and android-plugin dependencies and can run safely in both the
/// main isolate and a background isolate.
class SyncEngine {
  /// Called just before [wallet.syncToHeight] begins.
  final void Function(int startHeight, int endHeight) onSyncStarted;

  /// Called when [wallet.syncToHeight] finishes or throws. [success] is false
  /// on error so callers can deactivate progress indicators in both cases.
  final void Function(bool success) onSyncComplete;

  final Future<void> Function(String encodedUpdate) onStateUpdate;

  final String _logTag;

  bool _isSyncing = false;
  bool get isSyncing => _isSyncing;
  Completer<void>? _idleCompleter;

  late final StreamSubscription _syncResultSubscription;

  final _ownedOutputsRepository = OwnedOutputsRepository.instance;
  final _transactionsRepository = TransactionsRepository.instance;
  final _walletRepository = WalletRepository.instance;

  SyncEngine({
    required this.onSyncStarted,
    required this.onSyncComplete,
    required this.onStateUpdate,
    String logTag = 'sync',
  }) : _logTag = logTag {
    _syncResultSubscription = createSyncResultStream().listen(_onSyncResult);
  }

  Future<void> _onSyncResult(StateUpdate event) =>
      onStateUpdate(event.encode());

  Future<void> trySync() async {
    if (_isSyncing) {
      Logger().i('[$_logTag] sync already in progress, skipping');
      return;
    }
    _isSyncing = true;
    try {
      final wallet = await _walletRepository.readWallet();
      if (wallet == null) {
        Logger().i('[$_logTag] no wallet, skipping');
        return;
      }

      final network = await _walletRepository.readNetwork();
      final settings = SettingsRepository.instance;
      final blindbitUrl =
          await settings.getBlindbitUrl() ?? network.defaultBlindbitUrl;

      final correctNetwork =
          await checkNetwork(blindbitUrl: blindbitUrl, network: network);
      if (!correctNetwork) {
        Logger().w('[$_logTag] wrong network, skipping');
        return;
      }

      final tip = await getChainHeight(blindbitUrl: blindbitUrl);
      var lastSync = await _walletRepository.readLastSync();

      if (lastSync == null) {
        lastSync = await _heightFromBirthday(network);
        await _walletRepository.saveLastSync(lastSync);
        Logger()
            .i('[$_logTag] initialized lastSync to birthday height $lastSync');
      }

      if (lastSync >= tip) {
        Logger().i('[$_logTag] up to date (lastSync=$lastSync tip=$tip)');
        return;
      }

      Logger().i('[$_logTag] syncing $lastSync -> $tip');

      final dustLimit = await settings.getDustLimit() ?? defaultDustLimit;

      onSyncStarted(lastSync + 1, tip);

      final unconfirmedSpentOutpoints =
          await _transactionsRepository.getUnconfirmedSpentOutpoints();
      final unspentOutpoints =
          await _ownedOutputsRepository.getUnspentOutpoints();
      final ownedOutpoints = [
        ...unconfirmedSpentOutpoints,
        ...unspentOutpoints
      ];

      await wallet.syncToHeight(
          fromHeight: lastSync + 1,
          toHeight: tip,
          blindbitUrl: blindbitUrl,
          dustLimit: BigInt.from(dustLimit),
          ownedOutpoints: ownedOutpoints);

      Logger().i('[$_logTag] sync complete, tip=$tip');
      onSyncComplete(true);
    } catch (e) {
      Logger().e('[$_logTag] sync error: $e');
      onSyncComplete(false);
    } finally {
      _isSyncing = false;
      _idleCompleter?.complete();
      _idleCompleter = null;
    }
  }

  /// Waits until any active [trySync] call has fully unwound, including its
  /// [onSyncComplete] callback. Returns immediately if idle.
  ///
  /// [timeout] guards against Rust taking too long to honour [interruptSync].
  Future<void> waitForIdle({
    Duration timeout = const Duration(seconds: 5),
  }) {
    if (!_isSyncing) return Future.value();
    _idleCompleter ??= Completer<void>();
    return _idleCompleter!.future.timeout(timeout, onTimeout: () {});
  }

  Future<int> _heightFromBirthday(network) async {
    final birthday = await _walletRepository.readBirthday() ?? defaultBirthday;
    final mempoolApi = MempoolApiRepository(network: network);
    final block = await mempoolApi.getBlockFromTimestamp(birthday.toSeconds());
    return block.height;
  }

  void dispose() {
    _syncResultSubscription.cancel();
  }
}
