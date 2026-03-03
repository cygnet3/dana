import 'dart:async';
import 'dart:io';
import 'package:danawallet/constants.dart';
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

  // first sync will set the start height, all other syncs will keep the same height
  // this is useful if we receive an error while syncing, and restart the sync process.
  // this way, we make it explicit that we're continuing from the last sync,
  // instead of completely restarting.
  int? _startHeight;

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
      // if we just recovered a wallet, we haven't set the lastScan variable yet.
      Logger().d("Setting last scan to block height of birthday");
      try {
        await _initializeLastScan();
      } catch (e) {
        Logger().e("Error initializing last scan: $e");
        return;
      }
    }

    if (walletState.lastScan! < chainState.tip) {
      if (!scanProgress.scanning) {
        Logger().i("Starting sync");

        // set start height if not yet set
        _startHeight ??= walletState.lastScan!;

        await scanProgress.scan(walletState, _startHeight!, chainState.tip);
      }
    }

    if (chainState.tip < walletState.lastScan!) {
      // not sure what we should do here, that's really bad
      Logger().e('Current height is less than wallet last scan');
    }
  }

  Future<void> _initializeLastScan() async {
    // if wallet birthday isn't known, use the default birthday timestamp
    final timestamp = walletState.birthday ?? defaultBirthday;

    final blockHeight = await chainState.getBlockHeightFromDate(timestamp);

    walletState.lastScan = blockHeight;
  }

  void stopSyncTimer() {
    Logger().i("Stopping sync service");
    _timer?.cancel();
  }

  void clearSyncHistory() {
    _startHeight = null;
  }
}
