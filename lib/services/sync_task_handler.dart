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
  bool _initialized = false;
  SyncEngine? _engine;
  int? _startHeight;
  int? _endHeight;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    Logger().i('[BG] service started (starter: ${starter.name})');
    await _ensureInit();
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
    _engine!.trySync();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    Logger().i('[BG] heartbeat $timestamp');
    _engine?.trySync();
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
        Logger().i('[BG] sync triggered by main isolate');
        if (_engine?.isSyncing == true &&
            _startHeight != null &&
            _endHeight != null) {
          // Re-send current sync state so a freshly started main isolate can
          // pick up the progress bar.
          Logger().i('[BG] sync already running, re-sending progress state');
          FlutterForegroundTask.sendDataToMain({
            bgKeyStartHeight: _startHeight,
            bgKeyEndHeight: _endHeight,
          });
        } else {
          _engine?.trySync();
        }
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

  Future<void> _ensureInit() async {
    if (_initialized) return;
    await RustLib.init();
    _initialized = true;
  }
}
