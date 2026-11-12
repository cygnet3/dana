import 'dart:async';

import 'package:danawallet/services/sync_engine.dart';
import 'package:danawallet/states/sync_offline_state.dart';
import 'package:danawallet/states/sync_progress_state.dart';
import 'package:danawallet/states/wallet_state.dart';

/// In-process equivalent of [SynchronizationTaskHandler].
///
/// Runs sync in the main isolate, so it works on Linux and as an Android
/// fallback when notification permission has not been granted. Sync stops
/// whenever the app is suspended by the OS — that trade-off is intentional.
class InProcessSyncService {
  final SyncEngine _engine;

  InProcessSyncService({
    required SyncProgressState syncProgress,
    required WalletState walletState,
    SyncOfflineState? syncOffline,
  }) : _engine = SyncEngine(
          logTag: 'in-process',
          onSyncStarted: (start, end) {
            syncProgress.activate(start, end);
          },
          onSyncComplete: (success) => syncProgress.deactivate(success),
          onStateUpdated: (lastSyncOnly) =>
              walletState.refreshAfterSync(lastSyncOnly: lastSyncOnly),
          onTransientOffline: (message) => syncOffline?.setOffline(message),
        );

  /// Test/alternate-host seam: run with a pre-built engine (injected fakes).
  InProcessSyncService.withEngine(this._engine);

  /// Ordered startup (owner ruling 2026-11-12): resolve the backend and
  /// start the frigate monitor (frigate resolution only) BEFORE the chain
  /// poller can fire any one-shot [trySync]. On a blindbit resolution this
  /// is a no-op — a monitor must never outlive its backend selection (D9).
  Future<void> start() => _engine.ensureFrigateMonitor();

  Future<void> trySync() => _engine.trySync();

  void dispose() {
    // Drop the monitor subscription (no-op on a blindbit resolution); the
    // engine's dispose cancels the beat timer and the result subscription.
    unawaited(_engine.stopFrigateMonitor());
    _engine.dispose();
  }
}
