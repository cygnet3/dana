import 'dart:async';

import 'package:danawallet/constants.dart';
import 'package:danawallet/data/enums/sync_enums.dart';
import 'package:danawallet/services/foreground_sync_service.dart';
import 'package:danawallet/services/in_process_sync_service.dart';
import 'package:danawallet/states/chain_state.dart';
import 'package:danawallet/states/permission_state.dart';
import 'package:danawallet/states/sync_progress_notifier.dart';
import 'package:danawallet/states/wallet_state.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:logger/logger.dart';

/// Platform-specific sync lifecycle strategy.
///
/// [SyncOrchestrator] holds one of these and delegates all platform I/O to it,
/// keeping itself free of [Platform], plugin, and process-lifecycle imports.
abstract class SyncBackend {
  Future<SyncStartResult> start();
  Future<void> startFallback();
  Future<void> stop();
}

/// Linux backend: runs sync in the main isolate via [InProcessSyncService].
class LinuxSyncBackend implements SyncBackend {
  final ChainState _chainState;
  final SyncProgressNotifier _syncProgress;
  final WalletState _walletState;

  InProcessSyncService? _service;

  LinuxSyncBackend({
    required ChainState chainState,
    required SyncProgressNotifier syncProgress,
    required WalletState walletState,
  })  : _chainState = chainState,
        _syncProgress = syncProgress,
        _walletState = walletState;

  @override
  Future<SyncStartResult> start() async {
    _service = InProcessSyncService(
      syncProgress: _syncProgress,
      walletState: _walletState,
    );
    _chainState.startChainPoller(true, onTipUpdated: _service!.trySync);
    return SyncStartResult.started;
  }

  // Fallback mode is the same as regular start for linux
  @override
  Future<void> startFallback() async {
    await start();
  }

  @override
  Future<void> stop() async {
    _chainState.stopChainPoller();
    await _syncProgress.interruptSync();
    _service?.dispose();
    _service = null;
  }
}

/// Android backend: starts an Android foreground service and wires IPC
/// callbacks. Falls back to in-process sync if the service cannot start
/// (e.g. notification permission permanently denied).
class AndroidSyncBackend implements SyncBackend {
  final ChainState _chainState;
  final PermissionState _permissionState;
  final SyncProgressNotifier _syncProgress;
  final WalletState _walletState;

  /// Called when the background isolate sends [bgKeyFatalError]. The backend
  /// has already committed to the foreground-service path by the time this
  /// fires, so the caller must trigger a restart to recover into fallback mode.
  final Future<void> Function() onFatalError;

  bool _callbacksRegistered = false;
  InProcessSyncService? _fallbackService;

  AndroidSyncBackend({
    required ChainState chainState,
    required PermissionState permissionState,
    required SyncProgressNotifier syncProgress,
    required WalletState walletState,
    required this.onFatalError,
  })  : _chainState = chainState,
        _permissionState = permissionState,
        _syncProgress = syncProgress,
        _walletState = walletState;

  @override
  Future<SyncStartResult> start() async {
    if (!_callbacksRegistered) {
      FlutterForegroundTask.addTaskDataCallback(_syncProgress.onServiceData);
      FlutterForegroundTask.addTaskDataCallback(_walletState.onServiceData);
      FlutterForegroundTask.addTaskDataCallback(_onServiceData);
      _callbacksRegistered = true;
    }

    await _permissionState.refresh();
    if (!_permissionState.notificationGranted) {
      if (await FlutterForegroundTask.isRunningService) {
        await ForegroundSyncService.instance.stop();
      }
      Logger().w('[AndroidSyncBackend] notification permission missing — '
          'falling back to in-process sync');
      return _startFallback();
    }

    await ForegroundSyncService.instance.start();

    if (await FlutterForegroundTask.isRunningService) {
      _chainState.startChainPoller(
        true,
        onTipUpdated: () async =>
            FlutterForegroundTask.sendDataToTask({bgKeySync: true}),
      );
      return SyncStartResult.started;
    }

    Logger().w('[AndroidSyncBackend] foreground service unavailable — '
        'falling back to in-process sync');
    return _startFallback();
  }

  @override
  Future<void> startFallback() async {
    _startFallback();
  }

  @override
  Future<void> stop() async {
    _chainState.stopChainPoller();
    if (_fallbackService != null) {
      // In-process path: SpWallet.interruptSync() targets the correct (main) isolate.
      await _syncProgress.interruptSync();
      _fallbackService!.dispose();
      _fallbackService = null;
    } else {
      // Foreground-service path: the sync runs in the BG isolate, so we must
      // send the interrupt via IPC and let it call SpWallet.interruptSync() there.
      // Wait for the resulting bgKeyComplete before stopping the service so the
      // BG isolate can finish cleanly rather than being killed mid-sync.
      FlutterForegroundTask.sendDataToTask({bgKeyInterrupt: true});
      await _syncProgress.waitForCompletion();
      await ForegroundSyncService.instance.stop();
    }
  }

  void _onServiceData(Object data) {
    if (data is Map && data[bgKeyFatalError] == true) {
      Logger().e('[AndroidSyncBackend] background isolate reported fatal error '
          '— restarting to recover into fallback mode');
      unawaited(onFatalError());
    }
  }

  SyncStartResult _startFallback() {
    _fallbackService = InProcessSyncService(
      syncProgress: _syncProgress,
      walletState: _walletState,
    );
    _chainState.startChainPoller(true, onTipUpdated: _fallbackService!.trySync);
    return SyncStartResult.fallback;
  }
}
