import 'package:danawallet/data/enums/sync_enums.dart';
import 'package:danawallet/services/sync_backend.dart';
import 'package:flutter/material.dart';

export 'package:danawallet/data/enums/sync_enums.dart'
    show SyncAppAction;
export 'package:danawallet/services/sync_backend.dart'
    show SyncBackend, LinuxSyncBackend, AndroidSyncBackend;

/// Owns the sync lifecycle and exposes [inProcessFallback] so that
/// [HomeScreen] can show an informational banner without knowing platform
/// details.
///
/// All platform I/O is delegated to the injected [SyncBackend], keeping this
/// class free of [Platform] checks, plugin calls, and [exit] invocations.
class SyncOrchestrator extends ChangeNotifier {
  final SyncBackend _backend;

  bool _inProcessFallback = false;
  bool _running = false;

  bool get inProcessFallback => _inProcessFallback;
  bool get isRunning => _running;

  SyncOrchestrator({required SyncBackend backend}) : _backend = backend;

  /// Idempotent. On Android, [AndroidSyncBackend] may show a dialog via its
  /// [onUiEvent] callback before this returns — call only after the navigator
  /// is live.
  Future<void> start() async {
    if (_running) return;
    _running = true;
    final result = await _backend.start();
    _inProcessFallback = result == SyncStartResult.fallback;
    if (_inProcessFallback) notifyListeners();
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    await _backend.stop();
    if (_inProcessFallback) {
      _inProcessFallback = false;
      notifyListeners();
    }
  }

  Future<void> restart() async {
    await stop();
    await start();
  }
}
