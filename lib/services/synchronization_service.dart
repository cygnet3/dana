import 'dart:async';
import 'dart:io';
import 'package:danawallet/constants.dart';
import 'package:danawallet/extensions/network.dart';
import 'package:danawallet/generated/rust/api/structs/network.dart';
import 'package:danawallet/generated/rust/api/wallet.dart';
import 'package:danawallet/global_functions.dart';
import 'package:danawallet/repositories/settings_repository.dart';
import 'package:danawallet/states/chain_state.dart';
import 'package:danawallet/states/sync_progress_notifier.dart';
import 'package:danawallet/states/wallet_state.dart';
import 'package:flutter/scheduler.dart';
import 'package:logger/logger.dart';

class SynchronizationService {
  WalletState walletState;
  ChainState chainState;
  SyncProgressState syncProgress;

  Timer? _timer;
  Completer? _completer;
  final Duration _interval = const Duration(seconds: 10);

  SynchronizationService(
      {required this.chainState,
      required this.walletState,
      required this.syncProgress});

  Future<void> startSyncTimer(bool immediate) async {
    Logger().i("Starting sync service");

    if (immediate) {
      _tryPerformTask();
    }
    await _scheduleNextTask();
  }

  Future<void> _tryPerformTask() async {
    if (Platform.isAndroid) {
      final appState = SchedulerBinding.instance.lifecycleState;

      if (appState == AppLifecycleState.resumed) {
        // only sync on android if app is in foreground
        await _performTask();
      } else {
        // todo: claim the wifi lock, so that we have internet access
        // to sync, even when the screen is off
        Logger().i("We are in background, skip sync");
      }
    } else {
      // for other platforms, we assume we always want to sync
      // todo: probably requires similar flow for iOS
      await _performTask();
    }
  }

  Future<void> _performTask() async {
    _completer = Completer();
    try {
      if (!chainState.available) {
        //attempt to reconnect to the chain state
        if (!await chainState.reconnect()) {
          return;
        }
      }

      // fetch new tip before syncing
      if (await _performChainUpdateTask()) {
        await _performSynchronizationTask();
      }
    } on Exception catch (e) {
      // todo: we should have a connection status with the server
      // e.g. a green or red circle based on whether we have connection issues
      displayError("Sync failed", e);
    }
    _completer?.complete();
  }

  Future<void> _scheduleNextTask() async {
    _timer = Timer(_interval, () async {
      await _tryPerformTask();
      if (chainState.initiated) {
        _scheduleNextTask();
      }
    });
  }

  Future<bool> _performChainUpdateTask() async {
    return await chainState.updateChainTip();
  }

  Future<void> _performSynchronizationTask() async {
    if (walletState.lastSync == null) {
      // if we just recovered a wallet, we haven't set the lastSync variable yet.
      Logger().d("Setting last sync to block height of birthday");
      try {
        await _initializeLastSync();
      } catch (e) {
        Logger().e("Error initializing last scan: $e");
        return;
      }
    }

    if (walletState.lastSync! < chainState.tip) {
      Logger().i("Starting sync");

      // set sync start height to next block after the last synced block
      final fromHeight = walletState.lastSync! + 1;
      final toHeight = chainState.tip;

      await syncProgress.activate(fromHeight, toHeight);

      try {
        await _syncToHeight(fromHeight, toHeight);
        // if we finished syncing, clear and deactivate the sync progress.
        syncProgress.deactivate(true);
      } catch (e) {
        // if we encountered an error, notify the sync progress to deactivate,
        // but don't clear sync progress in case we want to continue.
        syncProgress.deactivate(false);
      }
    }
  }

  Future<void> _syncToHeight(int fromHeight, int toHeight) async {
    final wallet = await walletState.getWalletFromSecureStorage();
    final settings = SettingsRepository.instance;
    final blindbitUrl = await settings.getBlindbitUrl() ??
        chainState.network.defaultBlindbitUrl;
    final dustLimit = await settings.getDustLimit() ?? defaultDustLimit;

    if (walletState.lastSync == null) {
      throw Exception("Last sync is null");
    }

    await wallet.syncToHeight(
      fromHeight: fromHeight,
      toHeight: toHeight,
      blindbitUrl: blindbitUrl,
      dustLimit: BigInt.from(dustLimit),
      ownedOutpoints: walletState.outpointsToScan,
    );
  }

  Future<void> _initializeLastSync() async {
    // if we're using regtest, we ignore the date and set last_sync to 0
    if (chainState.network == Network.regtest) {
      walletState.lastSync = 0;
      return;
    }

    // if wallet birthday isn't known, use the default birthday timestamp
    final timestamp = walletState.birthday ?? defaultBirthday;

    final blockHeight = await chainState.getBlockHeightFromDate(timestamp);

    walletState.lastSync = blockHeight;
  }

  Future<void> interrupt() async {
    Logger().i("Interrupting sync task");
    // interrupt currently running sync
    SpWallet.interruptSync();

    // wait until the task has completed
    await _completer?.future;
  }

  Future<void> reset() async {
    // interrupt the sync task
    await interrupt();
    // cancel the timer, don't run follow-up sync attempts
    _timer?.cancel();
  }
}
