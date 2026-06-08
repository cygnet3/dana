import 'dart:async';
import 'dart:io';

import 'package:danawallet/constants.dart';
import 'package:danawallet/data/enums/sync_enums.dart';
import 'package:danawallet/services/foreground_sync_service.dart';
import 'package:danawallet/services/in_process_sync_service.dart';
import 'package:danawallet/states/chain_state.dart';
import 'package:danawallet/states/permission_state.dart';
import 'package:danawallet/states/sync_progress_state.dart';
import 'package:danawallet/states/wallet_state.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:logger/logger.dart';

class SyncService {
  final ChainState _chainState;
  final SyncProgressState _syncProgress;
  final WalletState _walletState;
  final PermissionState _permissionState;

  /// Called when the background isolate sends [bgKeyFatalError]. The backend
  /// has already committed to the foreground-service path by the time this
  /// fires, so the caller must trigger a restart to recover into fallback mode.
  final Future<void> Function() onFatalError;

  bool _callbacksRegistered = false;

  // in case we are doing in-process syncing
  InProcessSyncService? _inProcessSyncService;

  SyncService({
    required ChainState chainState,
    required PermissionState permissionState,
    required SyncProgressState syncProgress,
    required WalletState walletState,
    required this.onFatalError,
  })  : _chainState = chainState,
        _permissionState = permissionState,
        _syncProgress = syncProgress,
        _walletState = walletState;

  Future<SyncStartResult> start() async {
    if (Platform.isAndroid) {
      // on android, we use a foreground task to sync
      if (await startForeground()) {
        return SyncStartResult.foreground;
      } else {
        // if starting the foreground stask failed, fall back to in-process
        startInProcess();
        return SyncStartResult.fallback;
      }
    } else {
      // on all other platforms, we use in-process by default
      startInProcess();
      return SyncStartResult.inProcess;
    }
  }

  Future<bool> startForeground() async {
    if (!_callbacksRegistered) {
      FlutterForegroundTask.addTaskDataCallback(_onServiceData);
      _callbacksRegistered = true;
    }

    await _permissionState.refresh();
    if (!_permissionState.notificationGranted) {
      if (await FlutterForegroundTask.isRunningService) {
        await ForegroundSyncService.stop();
      }
      Logger().w('Notification permission missing');
      return false;
    }
    await ForegroundSyncService.start();

    if (await FlutterForegroundTask.isRunningService) {
      _chainState.startChainPoller(
        true,
        onTipUpdated: () async =>
            FlutterForegroundTask.sendDataToTask({bgKeySync: true}),
        shouldSkipTick: () => _syncProgress.isSyncing,
      );
      return true;
    }

    Logger().w('Foreground service unavailable');
    return false;
  }

  void startInProcess() {
    _inProcessSyncService = InProcessSyncService(
      syncProgress: _syncProgress,
      walletState: _walletState,
    );
    _chainState.startChainPoller(
      true,
      onTipUpdated: _inProcessSyncService!.trySync,
      shouldSkipTick: () => _syncProgress.isSyncing,
    );
    return;
  }

  void _onServiceData(Object data) {
    if (data is! Map) return;

    if (data[bgKeyFatalError] == true) {
      Logger().e('Background isolate reported a fatal error');
      unawaited(onFatalError());
    }

    // sync progress update
    if (data.containsKey(bgKeyStartHeight) &&
        data.containsKey(bgKeyEndHeight)) {
      int startHeight = (data[bgKeyStartHeight] as num).toInt();
      int endHeight = (data[bgKeyEndHeight] as num).toInt();
      _syncProgress.activate(startHeight, endHeight);
    } else if (data.containsKey(bgKeyComplete)) {
      bool success = data[bgKeyComplete] as bool;
      _syncProgress.deactivate(success);
    }

    // walletState update
    if (data.containsKey(bgKeyRefresh)) {
      final lastSyncOnly = data[bgKeyRefresh] as bool;
      unawaited(_walletState.refreshAfterSync(lastSyncOnly: lastSyncOnly));
    }
  }

  Future<void> stop() async {
    _chainState.stopChainPoller();
    if (_inProcessSyncService != null) {
      // In-process path: SpWallet.interruptSync() targets the correct (main) isolate.
      await _syncProgress.interruptSync();
      _inProcessSyncService!.dispose();
      _inProcessSyncService = null;
    } else {
      // Foreground-service path: the sync runs in the BG isolate, so we must
      // send the interrupt via IPC and let it call SpWallet.interruptSync() there.
      // Wait for the resulting bgKeyComplete before stopping the service so the
      // BG isolate can finish cleanly rather than being killed mid-sync.
      FlutterForegroundTask.sendDataToTask({bgKeyInterrupt: true});
      await _syncProgress.waitForCompletion();
      await ForegroundSyncService.stop();
    }
  }
}
