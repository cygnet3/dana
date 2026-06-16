import 'dart:async';

import 'package:danawallet/data/enums/sync_enums.dart';
import 'package:danawallet/services/sync_service.dart';
import 'package:danawallet/states/chain_state.dart';
import 'package:danawallet/states/permission_state.dart';
import 'package:danawallet/states/sync_progress_state.dart';
import 'package:danawallet/states/wallet_state.dart';
import 'package:flutter/material.dart';

export 'package:danawallet/services/sync_service.dart' show SyncService;

/// Coordinates sync backend lifecycle and runtime reconfiguration.
///
/// This class serializes [start], [stop], and [restart] to avoid overlapping
/// backend transitions, and reacts to [PermissionState] changes by restarting
/// sync when running (for example after Android notification permission
/// changes). It also exposes [inProcessFallback] so UI layers can surface
/// degraded background-sync state without depending on platform details.
///
/// All platform-specific I/O remains inside the injected [SyncService].
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
          permissionState: permissionState,
        ),
        _permissionState = permissionState {
    _permissionState.addListener(_onPermissionStateChanged);
    _service.onFatalError = () => restart(fallbackMode: true);
  }

  /// Idempotent. Call only after the navigator is live.
  Future<void> start({bool fallbackMode = false}) async {
    if (_running) return;
    _running = true;
    try {
      if (fallbackMode) {
        _service.startInProcess();
        _setInProcessFallback(true);
      } else {
        final result = await _service.start();
        _setInProcessFallback(result == SyncStartResult.fallback);
      }
    } catch (_) {
      _running = false;
      rethrow;
    }
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    await _service.stop();
    _setInProcessFallback(false);
  }

  Future<void> restart({bool fallbackMode = false}) async {
    if (_running) {
      _running = false;
      await _service.stop();
    }
    _setInProcessFallback(false);

    _running = true;
    try {
      if (fallbackMode) {
        _service.startInProcess();
        _setInProcessFallback(true);
      } else {
        final result = await _service.start();
        _setInProcessFallback(result == SyncStartResult.fallback);
      }
    } catch (_) {
      _running = false;
      rethrow;
    }
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
