import 'dart:async';
import 'dart:io';
import 'package:danawallet/constants.dart';
import 'package:danawallet/extensions/sync_queue_item.dart';
import 'package:danawallet/global_functions.dart';
import 'package:danawallet/repositories/sync_queue_repository.dart';
import 'package:danawallet/states/chain_state.dart';
import 'package:danawallet/states/sync_progress_notifier.dart';
import 'package:danawallet/states/wallet_state.dart';
import 'package:flutter/scheduler.dart';
import 'package:logger/logger.dart';

class SynchronizationService {
  SyncQueueRepository queue = SyncQueueRepository();
  WalletState walletState;
  ChainState chainState;
  SyncProgressNotifier scanProgress;

  // the total number of blocks in the sync queue
  // this value is used to track total sync progress across different sync items
  int? _syncBlockCount;

  Timer? _timer;
  final Duration _interval = const Duration(seconds: 10);

  SynchronizationService(
      {required this.chainState,
      required this.walletState,
      required this.scanProgress});

  Future<void> startSyncTimer(bool immediate) async {
    Logger().i("Starting sync service");

    if (immediate) {
      await _tryPerformTask();
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
    Logger().i("last sync: ${walletState.lastSync}");
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
      // we only insert new sync queue items if we're currently not syncing
      if (_syncBlockCount == null) {
        final start = walletState.lastSync! + 1;
        final end = chainState.tip;
        await queue.insertNewSyncQueueItem(start, end);
        Logger().i("inserted new sync queue item: [$start ..= $end]");
        // sync height now no longer represents the height to which we are synced, but instead the height to which we have created queue objects
        walletState.updateSyncHeight(end);
      }
    }

    final blocksToSync = await queue.getBlockCountToSync();
    int synced;
    if (_syncBlockCount == null) {
      _syncBlockCount = blocksToSync;
      synced = 0;
    } else {
      synced = _syncBlockCount! - blocksToSync;
    }

    final queueItems = await queue.getQueueItems();
    for (final item in queueItems) {
      await scanProgress.scan(walletState, item, synced, _syncBlockCount!);
      Logger().i("scanned ${item.toMap()}");
    }

    // done syncing, clear history
    clearSyncHistory();
  }

  Future<void> _initializeLastSync() async {
    // if wallet birthday isn't known, use the default birthday timestamp
    final timestamp = walletState.birthday ?? defaultBirthday;

    final blockHeight = await chainState.getBlockHeightFromDate(timestamp);

    walletState.lastSync = blockHeight;
  }

  void stopSyncTimer() {
    Logger().i("Stopping sync service");
    _timer?.cancel();
  }

  void clearSyncHistory() {
    scanProgress.reset();
    _syncBlockCount = null;
  }
}
