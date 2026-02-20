import 'dart:async';
import 'dart:io';
import 'package:danawallet/global_functions.dart';
import 'package:danawallet/states/chain_state.dart';
import 'package:danawallet/states/scan_progress_notifier.dart';
import 'package:danawallet/states/wallet_state.dart';
import 'package:flutter/scheduler.dart';
import 'package:logger/logger.dart';

class SynchronizationService {
  WalletState walletState;
  ChainState chainState;
  ScanProgressNotifier scanProgress;

  Timer? _timer;
  final Duration _interval = const Duration(seconds: 10);

  SynchronizationService(
      {required this.chainState,
      required this.walletState,
      required this.scanProgress});

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
    if (walletState.lastScan == null) {
      // This means we just setup the wallet, or we didn't have network so far. Try to set last scan to block height of birthday
      Logger().d("Setting last scan to block height of birthday");
      // In case we're migrating an older wallet and we didn't have network, birthday is null and needs to be resolved first
      if (walletState.birthday == null) {
        Logger().d("Birthday is null, trying to resolve it");
        await walletState.setBirthday();
      }
      if (walletState.birthday != null) {
        try {
          final height = await chainState.getBlockHeightFromDate(walletState.birthday!);
          walletState.lastScan = height;
        } catch (e) {
          Logger().e("Error getting last scan: $e");
          // We wait and try again later
          return;
        }
      } else {
        Logger().e("Birthday is still null, cannot set last scan");
        return;
      }
    }

    if (walletState.lastScan! < chainState.tip) {
      if (!scanProgress.scanning) {
        Logger().i("Starting sync");
        await scanProgress.scan(walletState);
      }
    }

    if (chainState.tip < walletState.lastScan!) {
      // not sure what we should do here, that's really bad
      Logger().e('Current height is less than wallet last scan');
    }
  }

  void stopSyncTimer() {
    Logger().i("Stopping sync service");
    _timer?.cancel();
  }
}
