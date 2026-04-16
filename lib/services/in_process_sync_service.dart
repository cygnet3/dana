import 'package:danawallet/services/sync_engine.dart';
import 'package:danawallet/states/sync_progress_notifier.dart';
import 'package:danawallet/states/wallet_state.dart';

/// In-process equivalent of [SynchronizationTaskHandler].
///
/// Runs sync in the main isolate, so it works on Linux and as an Android
/// fallback when notification permission has not been granted. Sync stops
/// whenever the app is suspended by the OS — that trade-off is intentional.
class InProcessSyncService {
  final SyncEngine _engine;

  InProcessSyncService({
    required SyncProgressNotifier syncProgress,
    required WalletState walletState,
  }) : _engine = SyncEngine(
          logTag: 'in-process',
          onSyncStarted: (start, end) {
            syncProgress.startHeight = start;
            syncProgress.endHeight = end;
            syncProgress.activate();
          },
          onSyncComplete: (_) => syncProgress.deactivate(),
          onStateUpdated: walletState.refreshAfterSync,
        );

  Future<void> trySync() => _engine.trySync();

  void dispose() => _engine.dispose();
}
