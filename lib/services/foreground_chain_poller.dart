import 'dart:async';

import 'package:danawallet/states/chain_state.dart';
import 'package:logger/logger.dart';

const Duration pollingInterval = Duration(seconds: 10);

/// Periodically refreshes the chain tip so the UI shows the current height.
/// Scanning is handled by the foreground service on Android.
class ForegroundChainPoller {
  final ChainState chainState;

  /// Called after a successful chain-tip update. Set via [startChainPoller]
  /// to decouple platform knowledge from this class.
  Future<void> Function()? onTipUpdated;
  bool Function()? shouldSkipTick;

  Timer? _timer;
  bool _running = false;

  ForegroundChainPoller({required this.chainState, this.onTipUpdated});

  void start() {
    Logger().i('Starting chain tip refresh timer');
    if (_running) return;
    _running = true;
    _scheduleNext();
  }

  void triggerImmediateUpdate() {
    if (!_running) return;
    _timer?.cancel();
    _timer = null;
    _performChainUpdate().then((_) {
      if (_running) _scheduleNext();
    });
  }

  void _scheduleNext() {
    _timer = Timer(pollingInterval, () async {
      await _performChainUpdate();
      if (!_running) return;
      if (!chainState.initiated) {
        Logger().i('Stopping chain poller: chain state no longer initialized');
        stop();
        return;
      }
      _scheduleNext();
    });
  }

  Future<void> _performChainUpdate() async {
    if (shouldSkipTick?.call() == true) {
      // Skip polling while sync is active.
      return;
    }

    try {
      var updated = false;
      if (!chainState.available) {
        // Recover from transient disconnects by re-establishing the chain
        // connection before attempting to refresh the tip.
        updated = await chainState.reconnect();
      } else {
        updated = await chainState.updateChainTip();
      }

      if (updated && shouldSkipTick?.call() != true) {
        await onTipUpdated?.call();
      }
    } catch (e) {
      Logger().e('Chain tip update failed: $e');
    }
  }

  void stop() {
    Logger().i('Stopping chain tip refresh timer');
    _running = false;
    _timer?.cancel();
    _timer = null;
  }
}
