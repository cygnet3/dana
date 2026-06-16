import 'dart:async';
import 'dart:io';

import 'package:danawallet/services/sync_service.dart';
import 'package:danawallet/states/chain_state.dart';
import 'package:danawallet/states/permission_state.dart';
import 'package:danawallet/states/sync_progress_state.dart';
import 'package:danawallet/states/wallet_state.dart';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';

class SyncOrchestrator extends ChangeNotifier {
  final SyncService _service;
  final PermissionState _permissionState;

  bool _inProcessFallback = false;
  bool _running = false;
  bool _permissionRestartInFlight = false;
  bool _disposed = false;

  bool get inProcessFallback => _inProcessFallback;
  bool get isRunning => _running;

  SyncOrchestrator({
    required ChainState chainState,
    required PermissionState permissionState,
    required SyncProgressState syncProgress,
    required WalletState walletState,
  })  : _service = SyncService(
          chainState: chainState,
          syncProgress: syncProgress,
          walletState: walletState,
        ),
        _permissionState = permissionState {
    _permissionState.addListener(_onPermissionStateChanged);
    _service.onFatalError = () => restart(forceInProcess: true);
  }

  Future<void> start({bool forceInProcess = false}) async {
    if (_running) return;

    bool tryForegroundTask = Platform.isAndroid &&
        _permissionState.notificationGranted &&
        !forceInProcess;

    if (tryForegroundTask) {
      final success = await _service.startForeground();
      if (success) {
        Logger().i("Successfully started foreground sync service");
        _setInProcessFallback(false);
      } else {
        Logger().w("Starting in-process service as a fallback");
        _service.startInProcess();
        _setInProcessFallback(true);
      }
    } else {
      // for non-android platforms, we always start the sync service in-process
      _service.startInProcess();
      Logger().i("Successfully started in-process sync service");
      _setInProcessFallback(false);
    }
    _running = true;
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    await _service.stop();
    _setInProcessFallback(false);
  }

  Future<void> restart({bool forceInProcess = false}) async {
    await stop();

    await start(forceInProcess: forceInProcess);
  }

  void _setInProcessFallback(bool value) {
    if (_inProcessFallback == value) return;
    _inProcessFallback = value;
    notifyListeners();
  }

  void _onPermissionStateChanged() {
    if (!_running || _permissionRestartInFlight) return;
    _permissionRestartInFlight = true;
    unawaited(() async {
      try {
        await restart();
      } finally {
        _permissionRestartInFlight = false;
      }
    }());
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _permissionState.removeListener(_onPermissionStateChanged);
    super.dispose();
  }
}
