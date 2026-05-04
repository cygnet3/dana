import 'dart:async';

import 'package:danawallet/constants.dart';
import 'package:danawallet/generated/rust/frb_generated.dart';
import 'package:danawallet/generated/rust/api/wallet.dart';
import 'package:danawallet/services/sync_engine.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:logger/logger.dart';

final ForegroundTaskOptions synchronizationTaskOptions = ForegroundTaskOptions(
  eventAction:
      ForegroundTaskEventAction.repeat(const Duration(hours: 1).inMilliseconds),
  autoRunOnBoot: true,
  autoRunOnMyPackageReplaced: true,
  allowWakeLock: false,
  allowWifiLock: false,
);

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(SynchronizationTaskHandler());
}

class SynchronizationTaskHandler extends TaskHandler {
  Future<void>? _initFuture;
  SyncEngine? _engine;
  int? _startHeight;
  int? _endHeight;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // First guard against accidental double calls
    if (_engine != null) {
      Logger().e('[BG] service already started, skipping');
      return;
    }

    Logger().i('[BG] service started (starter: ${starter.name})');
    try {
      await _ensureInit();
    } catch (e) {
      Logger()
          .e('[BG] Rust library failed to initialize — stopping service: $e');
      FlutterForegroundTask.sendDataToMain({bgKeyFatalError: true});
      await FlutterForegroundTask.stopService();
      return;
    }
    if (!await _ensureNotificationPermissionOrStop('onStart')) return;

    _engine = SyncEngine(
      logTag: 'BG',
      onSyncStarted: (start, end) {
        _startHeight = start;
        _endHeight = end;
        FlutterForegroundTask.sendDataToMain({
          bgKeyStartHeight: start,
          bgKeyEndHeight: end,
        });
      },
      onSyncComplete: (ok) {
        _startHeight = null;
        _endHeight = null;
        FlutterForegroundTask.sendDataToMain({bgKeyComplete: ok});
      },
      onStateUpdated: () async =>
          FlutterForegroundTask.sendDataToMain({bgKeyRefresh: true}),
    );
    unawaited(_engine!.trySync());
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    Logger().i('[BG] heartbeat $timestamp');
    unawaited(_onRepeatEventAsync());
  }

  Future<void> _onRepeatEventAsync() async {
    if (!await _ensureNotificationPermissionOrStop('onRepeatEvent')) return;
    await _ensureInit();
    unawaited(_engine?.trySync());
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    Logger().i('[BG] service destroyed (isTimeout: $isTimeout)');
    if (_engine?.isSyncing == true) {
      SpWallet.interruptSync();
      if (!isTimeout) {
        // Wait for trySync to drain so its onSyncComplete callback sends
        // bgKeyComplete to the main isolate before we cancel the subscription
        // in dispose(). This also prevents a double bgKeyComplete send.
        // Skipped on timeout: the OS is reclaiming the service immediately and
        // IPC delivery is not guaranteed; the main isolate's waitForCompletion
        // timeout will deactivate the progress bar on its own.
        await _engine!.waitForIdle();
      }
    }
    _engine?.dispose();
    _engine = null;
    _startHeight = null;
    _endHeight = null;
  }

  @override
  void onReceiveData(Object data) {
    if (data is Map) {
      if (data[bgKeySync] == true) {
        unawaited(_onReceiveSyncRequest());
      } else if (data[bgKeyInterrupt] == true) {
        Logger().i('[BG] interrupt requested');
        SpWallet.interruptSync();
        // onSyncComplete fires naturally once interruptSync() takes effect,
        // which sends bgKeyComplete to the main isolate and resolves its completer.
      } else {
        Logger().e('[BG] invalid data received: $data');
      }
    } else {
      Logger().e('[BG] invalid data received: $data');
    }
  }

  Future<void> _ensureInit() {
    _initFuture ??= RustLib.init();
    return _initFuture!;
  }

  /// Returns false if [NotificationPermission] is not granted and this task
  /// has shut down the foreground service — caller must not sync afterward.
  Future<bool> _ensureNotificationPermissionOrStop(String context) async {
    final perm = await FlutterForegroundTask.checkNotificationPermission();
    if (perm == NotificationPermission.granted) return true;

    Logger().w(
      '[BG] notification permission not granted ($context) — stopping '
      'foreground service',
    );
    await FlutterForegroundTask.stopService();
    return false;
  }

  Future<void> _onReceiveSyncRequest() async {
    if (!await _ensureNotificationPermissionOrStop('onReceiveData')) return;

    if (_engine?.isSyncing == true &&
        _startHeight != null &&
        _endHeight != null) {
      Logger().i('[BG] sync already running, re-sending progress state');
      FlutterForegroundTask.sendDataToMain({
        bgKeyStartHeight: _startHeight,
        bgKeyEndHeight: _endHeight,
      });
    } else {
      Logger().i('[BG] sync triggered by main isolate');
      await _ensureInit();
      unawaited(_engine?.trySync());
    }
  }
}
